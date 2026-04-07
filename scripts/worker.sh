#!/bin/bash
# worker.sh <role> — polls bus for tasks matching role, executes them

source /agent/scripts/helpers.sh

ROLE="${1}"
if [ -z "$ROLE" ]; then
  echo "Usage: worker.sh <architect|developer|qa|devops>"
  exit 1
fi

echo "⚙️  Worker started: $ROLE"

while true; do
  # Try to claim a task
  TASK_FILE=$(bus_claim_task "$ROLE")

  if [ -z "$TASK_FILE" ] || [ ! -f "$TASK_FILE" ]; then
    sleep 10
    continue
  fi

  TASK=$(cat "$TASK_FILE")
  TASK_ID=$(echo "$TASK"    | jq -r '.id')
  DESC=$(echo "$TASK"       | jq -r '.description')
  DEPENDS=$(echo "$TASK"    | jq -r '.depends_on | join(",")')
  ISSUE=$(basename "$TASK_FILE" | grep -o 'issue-[0-9]*' | head -1 | cut -d- -f2)
  WORKSPACE="$WORKSPACES/issue-${ISSUE}"
  LOG="$LOGS/issue-${ISSUE}-${TASK_ID}.log"

  echo "[${ROLE}] Starting task ${TASK_ID} for issue #${ISSUE}: ${DESC}"

  # Wait for dependencies to complete
  if [ -n "$DEPENDS" ]; then
    echo "[${ROLE}] Waiting for dependencies: $DEPENDS"
    IFS=',' read -ra DEPS <<< "$DEPENDS"
    for dep in "${DEPS[@]}"; do
      while [ ! -f "$BUS/done/issue-${ISSUE}-${dep}.json" ]; do
        sleep 5
      done
    done
    echo "[${ROLE}] Dependencies satisfied"
  fi

  telegram_message "⚙️ *[${ROLE}] Starting task*
Issue #${ISSUE} / ${TASK_ID}
_${DESC}_"

  # Dispatch to role handler
  case "$ROLE" in
    architect) source /agent/scripts/roles/architect.sh && run_architect "$ISSUE" "$DESC" "$WORKSPACE" ;;
    developer) source /agent/scripts/roles/developer.sh && run_developer "$ISSUE" "$DESC" "$WORKSPACE" ;;
    qa)        source /agent/scripts/roles/qa.sh        && run_qa        "$ISSUE" "$DESC" "$WORKSPACE" ;;
    devops)    source /agent/scripts/roles/devops.sh    && run_devops    "$ISSUE" "$DESC" "$WORKSPACE" ;;
  esac

  EXIT_CODE=$?

  if [ $EXIT_CODE -eq 0 ]; then
    echo "[${ROLE}] ✅ Task ${TASK_ID} completed"
    bus_complete_task "$TASK_FILE"
    telegram_message "✅ *[${ROLE}] Task done*
Issue #${ISSUE} / ${TASK_ID}"
  else
    echo "[${ROLE}] ❌ Task ${TASK_ID} failed (exit $EXIT_CODE)"
    # Put back in queue with failure flag so coordinator can decide
    jq '. + {"failed": true, "fail_count": ((.fail_count // 0) + 1)}' \
      "$TASK_FILE" > /tmp/task_retry.json
    # Retry up to 2 times, then abandon
    FAIL_COUNT=$(jq -r '.fail_count // 0' /tmp/task_retry.json)
    if [ "$FAIL_COUNT" -lt 3 ]; then
      mv /tmp/task_retry.json "$BUS/queue/$(basename "$TASK_FILE")"
      telegram_message "⚠️ *[${ROLE}] Task failed — retrying*
Issue #${ISSUE} / ${TASK_ID} (attempt $((FAIL_COUNT+1))/3)"
    else
      mv /tmp/task_retry.json "$BUS/done/FAILED-$(basename "$TASK_FILE")"
      telegram_message "❌ *[${ROLE}] Task permanently failed*
Issue #${ISSUE} / ${TASK_ID}
Check: \`/logs ${ISSUE}\`"
      issue_comment "$ISSUE" "❌ Agent task \`${TASK_ID}\` failed after 3 attempts. Manual intervention needed. Role: **${ROLE}**"
    fi
  fi
done
