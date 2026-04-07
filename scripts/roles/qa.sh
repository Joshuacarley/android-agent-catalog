#!/bin/bash
# roles/qa.sh

run_qa() {
  local issue="$1" desc="$2" workspace="$3"

  DEV_NOTES=$(cat "$workspace/DEVELOPER_NOTES.md" 2>/dev/null || echo "")
  APK="${workspace}/app/build/outputs/apk/debug/app-debug.apk"

  if [ ! -f "$APK" ]; then
    echo "❌ APK not found at $APK"
    return 1
  fi

  # Boot the emulator
  boot_emulator || return 1

  # Install APK
  adb install -r "$APK"
  echo "✅ APK installed"

  # Start recording
  adb shell "screenrecord --bit-rate 4000000 /sdcard/test_recording.mp4" &
  RECORD_PID=$!
  sleep 2

  # Let Claude drive the app using adb
  claude --print \
    --allowedTools "Bash,Read,Write" \
    "You are a QA Engineer testing an Android app on an emulator.

Your task: ${desc}

What the developer changed:
${DEV_NOTES}

The app is installed and the emulator is running. Screen recording has started.

Use adb to test the app thoroughly:
- adb shell input tap X Y          (tap at coordinates)
- adb shell input swipe X1 Y1 X2 Y2 500  (swipe)
- adb shell input text 'string'    (type text)
- adb shell input keyevent 66      (ENTER key)
- adb shell input keyevent 4       (BACK key)
- adb shell screencap /sdcard/screen.png && adb pull /sdcard/screen.png /tmp/screen.png

Steps:
1. Take a screenshot to see the current state: screencap + pull
2. Navigate to the feature described in the task
3. Test the happy path — does the feature work as expected?
4. Test 2-3 edge cases
5. Take screenshots at key moments
6. Write QA.md with:
   ## Test Results
   - PASS/FAIL for each scenario
   ## Screenshots Taken
   - List what each screenshot shows
   ## Bugs Found
   - Any unexpected behavior
   ## Verdict
   - APPROVED or NEEDS_FIXES with specific notes" \
    --cwd "$workspace" 2>&1 | tee "$LOGS/issue-${issue}-qa.log"

  # Stop recording
  kill $RECORD_PID 2>/dev/null || true
  adb shell "pkill -SIGINT screenrecord" 2>/dev/null || true
  sleep 3

  # Pull and compress video
  VIDEO=$(stop_screen_record "$issue")

  # Pull screenshots
  mkdir -p "$LOGS/issue-${issue}-screenshots"
  adb pull /sdcard/screen.png "$LOGS/issue-${issue}-screenshots/" 2>/dev/null || true

  stop_emulator

  # Check verdict
  if grep -q "APPROVED" "$workspace/QA.md" 2>/dev/null; then
    bus_post_message "qa" "devops" "$issue" "$(cat "$workspace/QA.md")"

    # Send first screenshot preview to Telegram
    local first_shot
    first_shot=$(ls "$LOGS/issue-${issue}-screenshots/"*.png 2>/dev/null | head -1)
    if [ -n "$first_shot" ]; then
      telegram_photo "$first_shot" "📱 QA screenshot — issue #${issue}"
    fi
    return 0
  else
    telegram_message "⚠️ *QA found issues on #${issue}*
$(grep -A5 'Bugs Found' "$workspace/QA.md" 2>/dev/null | head -6)"
    return 1
  fi
}
