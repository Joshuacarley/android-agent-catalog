#!/bin/bash
# helpers.sh — shared functions for all agent scripts

TELEGRAM_TOKEN="${TELEGRAM_TOKEN}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID}"
REPO="${GITHUB_REPO}"
BUS="/agent/bus"
WORKSPACES="/agent/workspaces"
LOGS="/agent/logs"
BUILDS="/builds"

# ── Telegram ──────────────────────────────────────────────────

telegram_message() {
  local text="$1"
  curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d text="$text" \
    -d parse_mode="Markdown" > /dev/null
}

telegram_apk() {
  local path="$1" caption="$2"
  curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendDocument" \
    -F chat_id="$TELEGRAM_CHAT_ID" \
    -F document=@"$path" \
    -F caption="$caption" \
    -F parse_mode="Markdown" > /dev/null
}

telegram_video() {
  local path="$1" caption="$2"
  curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendVideo" \
    -F chat_id="$TELEGRAM_CHAT_ID" \
    -F video=@"$path" \
    -F caption="$caption" \
    -F supports_streaming="true" \
    -F parse_mode="Markdown" > /dev/null
}

telegram_photo() {
  local path="$1" caption="$2"
  curl -s -X POST \
    "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendPhoto" \
    -F chat_id="$TELEGRAM_CHAT_ID" \
    -F photo=@"$path" \
    -F caption="$caption" > /dev/null
}


# ── Token tracking ────────────────────────────────────────────
TOKENS_LOG="/agent/logs/tokens.jsonl"

claude_tracked() {
  # Wrapper around claude --print that captures and logs token usage
  # Usage: claude_tracked <issue> <role> <task_id> [claude args...]
  local issue="$1" role="$2" task_id="$3"
  shift 3

  local tmp_out
  tmp_out=$(mktemp)

  # Run claude, capture full output
  claude --print "$@" 2>&1 | tee "$tmp_out"
  local exit_code=${PIPESTATUS[0]}

  # Parse token counts from Claude Code output
  # Claude Code prints: "Tokens: {input: X, output: Y, cache_read: Z}"
  local input_tokens output_tokens
  input_tokens=$(grep -oP '"?input"?:?\s*\K[0-9]+' "$tmp_out" 2>/dev/null | head -1 || echo 0)
  output_tokens=$(grep -oP '"?output"?:?\s*\K[0-9]+' "$tmp_out" 2>/dev/null | head -1 || echo 0)

  # Fallback: count approximate tokens from output size (4 chars ≈ 1 token)
  if [ "$input_tokens" -eq 0 ] 2>/dev/null; then
    local out_size
    out_size=$(wc -c < "$tmp_out")
    input_tokens=$((out_size / 4))
    output_tokens=$((out_size / 16))
  fi

  # Append to token log (JSONL format)
  local ts
  ts=$(date -Iseconds)
  echo "{"ts":"$ts","issue":"$issue","role":"$role","task":"$task_id","input":$input_tokens,"output":$output_tokens}" >> "$TOKENS_LOG"

  rm -f "$tmp_out"
  return $exit_code
}

# ── Bus / task locking ────────────────────────────────────────

bus_claim_task() {
  local role="$1"
  local task_file

  # Find a task for this role that isn't locked
  task_file=$(find "$BUS/queue" -name "*.json" \
    -exec sh -c 'grep -l "\"role\":\"'"$role"'\"" "$1" 2>/dev/null' _ {} \; \
    | head -1)

  [ -z "$task_file" ] && return 1

  local lock_file="${task_file}.lock"
  local dest="$BUS/in-progress/$(basename "$task_file")"

  # Atomic move with flock
  (
    flock -n 9 || return 1
    [ -f "$task_file" ] || return 1
    mv "$task_file" "$dest"
    echo "$dest"
  ) 9>"$lock_file"
}

bus_complete_task() {
  local task_file="$1"
  mv "$task_file" "$BUS/done/"
}

bus_post_message() {
  local from="$1" to="$2" issue="$3" content="$4"
  local ts
  ts=$(date +%s)
  echo "{\"from\":\"$from\",\"to\":\"$to\",\"issue\":\"$issue\",\"content\":$(echo "$content" | jq -Rs .)}" \
    > "$BUS/messages/${issue}-${from}-${to}-${ts}.json"
}

bus_read_messages() {
  local to="$1" issue="$2"
  find "$BUS/messages" -name "${issue}-*-${to}-*.json" \
    -exec jq -r '.content' {} \; 2>/dev/null
}

# ── Emulator ──────────────────────────────────────────────────

boot_emulator() {
  echo "🚀 Starting virtual display and emulator..."

  # Kill any existing Xvfb
  pkill Xvfb 2>/dev/null || true
  sleep 1

  # Start virtual framebuffer
  Xvfb :99 -screen 0 1080x1920x24 &
  export DISPLAY=:99
  sleep 2

  # Kill any existing emulator
  pkill -f "emulator.*Pixel_6" 2>/dev/null || true
  sleep 2

  # Boot emulator
  $ANDROID_HOME/emulator/emulator \
    -avd Pixel_6_API_34 \
    -no-window \
    -no-audio \
    -gpu swiftshader_indirect \
    -no-snapshot \
    -wipe-data \
    2>/tmp/emulator.log &

  echo "⏳ Waiting for emulator boot..."
  local attempts=0
  until adb shell getprop sys.boot_completed 2>/dev/null | grep -q "1"; do
    sleep 5
    attempts=$((attempts + 1))
    if [ $attempts -gt 36 ]; then
      echo "❌ Emulator failed to boot after 3 minutes"
      cat /tmp/emulator.log
      return 1
    fi
  done

  # Disable animations for faster/more reliable testing
  adb shell settings put global window_animation_scale 0
  adb shell settings put global transition_animation_scale 0
  adb shell settings put global animator_duration_scale 0
  echo "✅ Emulator ready"
}

stop_emulator() {
  adb emu kill 2>/dev/null || true
  pkill -f "emulator.*Pixel_6" 2>/dev/null || true
  pkill Xvfb 2>/dev/null || true
}

# ── Video ─────────────────────────────────────────────────────

start_screen_record() {
  adb shell "screenrecord --bit-rate 4000000 /sdcard/test_recording.mp4 &"
  echo $! > /tmp/screenrecord.pid
}

stop_screen_record() {
  local issue="$1"
  adb shell "pkill -l SIGINT screenrecord" 2>/dev/null || true
  sleep 3
  adb pull /sdcard/test_recording.mp4 "$LOGS/issue-${issue}-raw.mp4" 2>/dev/null || true

  if [ -f "$LOGS/issue-${issue}-raw.mp4" ]; then
    ffmpeg -i "$LOGS/issue-${issue}-raw.mp4" \
      -vcodec libx264 -crf 28 -preset fast \
      -vf "scale=720:-2" \
      "$LOGS/issue-${issue}-test.mp4" \
      -y -loglevel error
    echo "$LOGS/issue-${issue}-test.mp4"
  fi
}

# ── GitHub ────────────────────────────────────────────────────

issue_add_label() {
  gh issue edit "$1" --repo "$REPO" --add-label "$2"
}

issue_remove_label() {
  gh issue edit "$1" --repo "$REPO" --remove-label "$2" 2>/dev/null || true
}

issue_comment() {
  gh issue comment "$1" --repo "$REPO" --body "$2"
}
