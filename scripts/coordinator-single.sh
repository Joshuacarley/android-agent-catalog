#!/bin/bash
# coordinator-single.sh <issue_number>
# Manually trigger a single issue (called by Telegram /build command)

source /agent/scripts/helpers.sh

ISSUE_NUMBER="$1"
if [ -z "$ISSUE_NUMBER" ]; then
  echo "Usage: coordinator-single.sh <issue_number>"
  exit 1
fi

ISSUE_DATA=$(gh issue view "$ISSUE_NUMBER" --repo "$REPO" --json title,body)
TITLE=$(echo "$ISSUE_DATA" | jq -r '.title')
BODY=$(echo "$ISSUE_DATA"  | jq -r '.body')
WORKSPACE="$WORKSPACES/issue-${ISSUE_NUMBER}"

if [ -d "$WORKSPACE" ]; then
  telegram_message "⚠️ Issue #${ISSUE_NUMBER} already has a workspace.
Use /cancel ${ISSUE_NUMBER} first if you want to restart it."
  exit 1
fi

issue_add_label "$ISSUE_NUMBER" "in-progress"

telegram_message "🚀 *Manually triggered: #${ISSUE_NUMBER}*
_${TITLE}_"

mkdir -p "$WORKSPACE"
cd "$BUILDS"

git -C "$BUILDS" fetch origin main 2>/dev/null || true
git -C "$BUILDS" worktree add "$WORKSPACE" \
  -b "claude/issue-${ISSUE_NUMBER}" origin/main 2>/dev/null || true

claude --print \
  --allowedTools "Write,Read" \
  "You are a senior engineering coordinator for an Android app team.

Issue #${ISSUE_NUMBER}: ${TITLE}
---
${BODY}
---

Write TASKS.md with structured task JSON (one per line starting with {).
Roles available: architect, developer, qa, devops.
Be specific and actionable." \
  --cwd "$WORKSPACE" > "$WORKSPACE/TASKS.md" \
  2>&1 | tee "$LOGS/issue-${ISSUE_NUMBER}-planning.log"

TASK_COUNT=0
grep '^{' "$WORKSPACE/TASKS.md" | while read -r task; do
  TASK_ID=$(echo "$task" | jq -r '.id')
  echo "$task" > "$BUS/queue/issue-${ISSUE_NUMBER}-${TASK_ID}.json"
  TASK_COUNT=$((TASK_COUNT + 1))
done

TASK_COUNT=$(grep -c '^{' "$WORKSPACE/TASKS.md" || echo 0)

telegram_message "📋 *Issue #${ISSUE_NUMBER} queued*
${TASK_COUNT} tasks dispatched to the team."
