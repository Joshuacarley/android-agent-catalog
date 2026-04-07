#!/bin/bash
# coordinator-cron.sh — polls GitHub every N minutes, dispatches work

source /agent/scripts/helpers.sh

POLL_INTERVAL=${POLL_INTERVAL_SECONDS:-300}  # default 5 min
ISSUE_LABEL=${CLAUDE_ISSUE_LABEL:-"claude"}

echo "📋 Coordinator started. Polling every ${POLL_INTERVAL}s for label: ${ISSUE_LABEL}"

while true; do
  echo "[$(date)] Checking for new issues..."

  # Fetch open issues with our label that aren't already in-progress
  ISSUES=$(gh issue list \
    --repo "$REPO" \
    --label "$ISSUE_LABEL" \
    --state open \
    --json number,title,body,labels \
    --jq '.[] | select(.labels | map(.name) | contains(["in-progress"]) | not)')

  if [ -z "$ISSUES" ]; then
    echo "No new issues found."
    sleep "$POLL_INTERVAL"
    continue
  fi

  echo "$ISSUES" | jq -c '.' | while read -r issue; do
    NUMBER=$(echo "$issue" | jq -r '.number')
    TITLE=$(echo "$issue"  | jq -r '.title')
    BODY=$(echo "$issue"   | jq -r '.body')

    # Skip if workspace already exists (already being planned)
    WORKSPACE="$WORKSPACES/issue-${NUMBER}"
    if [ -d "$WORKSPACE" ]; then
      echo "Issue #${NUMBER} already has a workspace, skipping."
      continue
    fi

    echo "📥 New issue: #${NUMBER} — ${TITLE}"

    # Lock the issue immediately
    issue_add_label "$NUMBER" "in-progress"

    # Notify Telegram
    telegram_message "📥 *New issue picked up: #${NUMBER}*
_${TITLE}_
Planning tasks now..."

    # Create workspace
    mkdir -p "$WORKSPACE"
    cd "$BUILDS"

    # Set up git worktree
    if [ ! -d "$BUILDS/.git" ]; then
      gh repo clone "$REPO" "$BUILDS" -- --depth=1 2>/dev/null || true
    fi

    git -C "$BUILDS" fetch origin main
    git -C "$BUILDS" worktree add "$WORKSPACE" \
      -b "claude/issue-${NUMBER}" origin/main 2>/dev/null || \
    git -C "$BUILDS" worktree add "$WORKSPACE" "claude/issue-${NUMBER}" 2>/dev/null || true

    # Ask Claude to plan the work
    echo "🧠 Coordinator planning issue #${NUMBER}..."

    claude --print \
      --allowedTools "Write,Read" \
      "You are a senior engineering coordinator for an Android app team.

Analyze this GitHub issue and produce a structured task plan. Be very specific —
autonomous AI agents will execute each task without human input.

Issue #${NUMBER}: ${TITLE}
---
${BODY}
---

Write a file called TASKS.md. Include:
1. A brief summary of what needs to be done
2. Tasks formatted EXACTLY like this (one JSON per line, starting with {):
{\"id\":\"task-1\",\"role\":\"architect\",\"description\":\"Review existing auth module and write design notes for the new feature\",\"depends_on\":[]}
{\"id\":\"task-2\",\"role\":\"developer\",\"description\":\"Implement LoginViewModel changes in app/src/main/java/com/app/auth/LoginViewModel.kt\",\"depends_on\":[\"task-1\"]}
{\"id\":\"task-3\",\"role\":\"developer\",\"description\":\"Add unit tests in app/src/test/java/com/app/auth/LoginViewModelTest.kt\",\"depends_on\":[\"task-2\"]}
{\"id\":\"task-4\",\"role\":\"qa\",\"description\":\"Install APK, test login flow end to end, record screen\",\"depends_on\":[\"task-2\"]}
{\"id\":\"task-5\",\"role\":\"devops\",\"description\":\"Build release APK, send to Telegram, open PR\",\"depends_on\":[\"task-3\",\"task-4\"]}

Rules:
- Always start with an architect task
- Split developer work into per-file or per-module tasks (enables parallelism)
- QA task always depends on developer tasks
- DevOps task is always last
- Description must be actionable and specific enough for an AI to execute alone" \
      --cwd "$WORKSPACE" 2>&1 | tee "$LOGS/issue-${NUMBER}-planning.log"

    # Queue tasks to bus
    TASK_COUNT=0
    if [ -f "$WORKSPACE/TASKS.md" ]; then
      grep '^{' "$WORKSPACE/TASKS.md" | while read -r task; do
        TASK_ID=$(echo "$task" | jq -r '.id')
        echo "$task" > "$BUS/queue/issue-${NUMBER}-${TASK_ID}.json"
        TASK_COUNT=$((TASK_COUNT + 1))
      done
      TASK_COUNT=$(grep -c '^{' "$WORKSPACE/TASKS.md" || echo 0)
    fi

    telegram_message "📋 *Issue #${NUMBER} planned*
${TASK_COUNT} tasks queued across architect, developer, QA, and DevOps agents.

Tasks:
$(grep '^{' "$WORKSPACE/TASKS.md" 2>/dev/null | jq -r '"• [" + .role + "] " + .description' | head -8)"

    echo "✅ Issue #${NUMBER} queued with ${TASK_COUNT} tasks"
  done

  sleep "$POLL_INTERVAL"
done
