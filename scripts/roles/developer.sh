#!/bin/bash
# roles/developer.sh

run_developer() {
  local issue="$1" desc="$2" workspace="$3"

  REVIEW=$(cat "$workspace/REVIEW.md" 2>/dev/null || echo "No architect review yet.")
  TASKS=$(cat "$workspace/TASKS.md"   2>/dev/null || echo "")

  claude --print \
    --allowedTools "Edit,Write,Read,Bash" \
    "You are a Senior Android Developer (Kotlin, Jetpack Compose, MVVM, Coroutines).

Your task: ${desc}

## Architect's Review
${REVIEW}

## Full Task Plan
${TASKS}

## Instructions
1. Implement the task exactly as the architect described
2. Follow ALL patterns shown in the architect's review
3. After implementing, run: cd ${workspace} && ./gradlew assembleDebug
4. Fix every build error before finishing — do not stop until BUILD SUCCESSFUL
5. If tests exist for the files you changed, run: ./gradlew test
6. Write DEVELOPER_NOTES.md with:
   - What you changed and in which files
   - Why you made each decision
   - Any trade-offs or follow-up items

Do not modify build.gradle unless absolutely necessary.
Do not change minSdk, targetSdk, or dependencies without architect approval." \
    --cwd "$workspace" 2>&1 | tee "$LOGS/issue-${issue}-developer.log"

  # Verify build succeeded
  if grep -q "BUILD SUCCESSFUL" "$LOGS/issue-${issue}-developer.log"; then
    bus_post_message "developer" "qa" "$issue" "$(cat "$workspace/DEVELOPER_NOTES.md" 2>/dev/null)"
    return 0
  else
    echo "❌ Build did not succeed"
    return 1
  fi
}
