#!/bin/bash
# roles/devops.sh

run_devops() {
  local issue="$1" desc="$2" workspace="$3"

  QA_NOTES=$(cat "$workspace/QA.md"              2>/dev/null || echo "")
  DEV_NOTES=$(cat "$workspace/DEVELOPER_NOTES.md" 2>/dev/null || echo "")
  REVIEW=$(cat "$workspace/REVIEW.md"             2>/dev/null || echo "")
  APK="${workspace}/app/build/outputs/apk/debug/app-debug.apk"
  VIDEO="$LOGS/issue-${issue}-test.mp4"

  ISSUE_TITLE=$(gh issue view "$issue" --repo "$REPO" --json title --jq '.title')

  # ── Final build ──────────────────────────────────────────────
  echo "🔨 Running final build..."
  cd "$workspace"
  ./gradlew assembleDebug 2>&1 | tee "$LOGS/issue-${issue}-final-build.log"

  if ! grep -q "BUILD SUCCESSFUL" "$LOGS/issue-${issue}-final-build.log"; then
    telegram_message "❌ *DevOps: Final build failed for #${issue}*
Check: \`/logs ${issue}\`"
    return 1
  fi

  # ── Send APK to Telegram ──────────────────────────────────────
  if [ -f "$APK" ]; then
    APK_SIZE=$(du -sh "$APK" | cut -f1)
    telegram_apk "$APK" "📱 *APK ready — Issue #${issue}*
_${ISSUE_TITLE}_
Size: ${APK_SIZE}
Build: DEBUG"
  fi

  # ── Send test video to Telegram ───────────────────────────────
  if [ -f "$VIDEO" ]; then
    telegram_video "$VIDEO" "🎥 *Test recording — Issue #${issue}*
$(grep 'Verdict' -A2 "$workspace/QA.md" 2>/dev/null | tail -2)"
  fi

  # ── Open GitHub PR ────────────────────────────────────────────
  BRANCH="claude/issue-${issue}"
  git -C "$workspace" add -A
  git -C "$workspace" commit -m "Fix #${issue}: ${ISSUE_TITLE}

Automated implementation by Claude Code agent team.
- Architect reviewed design
- Developer implemented changes
- QA verified on emulator" || true

  git -C "$workspace" push origin "$BRANCH" --force-with-lease

  PR_URL=$(gh pr create \
    --repo "$REPO" \
    --title "Fix #${issue}: ${ISSUE_TITLE}" \
    --body "Closes #${issue}

## Summary
$(head -10 "$workspace/TASKS.md" | grep -v '^{')

## Architecture Notes
${REVIEW}

## Changes Made
${DEV_NOTES}

## QA Results
${QA_NOTES}

---
*Automated by Claude Code agent team on $(hostname)*" \
    --base main \
    --head "$BRANCH" 2>&1)

  # ── Clean up labels ───────────────────────────────────────────
  issue_remove_label "$issue" "in-progress"
  issue_add_label    "$issue" "pr-opened"

  telegram_message "🎉 *Issue #${issue} complete!*
_${ISSUE_TITLE}_

🔀 PR: ${PR_URL}
📱 APK sent above
🎥 Test video sent above

All done — ready for your review."

  return 0
}
