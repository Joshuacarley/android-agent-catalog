#!/bin/bash
# roles/architect.sh

run_architect() {
  local issue="$1" desc="$2" workspace="$3"

  claude --print \
    --allowedTools "Read,Write,Bash" \
    "You are the Lead Architect on an Android team (Kotlin, MVVM, Jetpack Compose).

Your task: ${desc}

Review the codebase thoroughly, then write REVIEW.md with:

## Architecture Decision
What pattern/approach to use and why.

## Files to Change
List every file the developer needs to touch with a brief note on what changes.

## Code Patterns to Follow
Show 1-2 short code examples from the existing codebase demonstrating patterns
the developer should mirror.

## Risks & Gotchas
Anything the developer should watch out for.

## Definition of Done
Specific, testable criteria the developer must meet before handing off to QA.

Be extremely specific. A developer AI agent will read REVIEW.md and implement
without asking questions." \
    --cwd "$workspace" 2>&1 | tee "$LOGS/issue-${issue}-architect.log"

  # Post review to message bus for other agents
  if [ -f "$workspace/REVIEW.md" ]; then
    bus_post_message "architect" "developer" "$issue" "$(cat "$workspace/REVIEW.md")"
    return 0
  else
    echo "❌ Architect failed to produce REVIEW.md"
    return 1
  fi
}
