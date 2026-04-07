#!/bin/bash
# scripts/healthcheck.sh
# Used by TrueNAS to report app health in the UI
# Also runnable manually: docker exec agent-coordinator /agent/scripts/healthcheck.sh

source /agent/scripts/helpers.sh 2>/dev/null || true

PASS=0
FAIL=0

check() {
  local name="$1"
  local result="$2"
  local expected="${3:-0}"
  if [ "$result" -eq "$expected" ] 2>/dev/null; then
    echo "  ✅ $name"
    PASS=$((PASS+1))
  else
    echo "  ❌ $name"
    FAIL=$((FAIL+1))
  fi
}

echo "=== Android Agent Health Check ==="
echo ""

# Claude Code
claude --version &>/dev/null
check "Claude Code installed" $?

# GitHub CLI
gh --version &>/dev/null
check "GitHub CLI installed" $?

# GitHub auth
gh auth status &>/dev/null
check "GitHub authenticated" $?

# Anthropic API key set
[ -n "$ANTHROPIC_API_KEY" ]
check "ANTHROPIC_API_KEY set" $?

# Telegram token set
[ -n "$TELEGRAM_TOKEN" ]
check "TELEGRAM_TOKEN set" $?

# GitHub repo set
[ -n "$GITHUB_REPO" ]
check "GITHUB_REPO set" $?

# Bus directories exist
[ -d "/agent/bus/queue" ]
check "Bus queue directory" $?

[ -d "/agent/bus/in-progress" ]
check "Bus in-progress directory" $?

# KVM accessible
[ -e "/dev/kvm" ]
check "KVM device accessible" $?

# Android SDK
[ -d "$ANDROID_HOME/emulator" ]
check "Android emulator" $?

[ -d "$ANDROID_HOME/platform-tools" ]
check "Android platform-tools" $?

# AVD exists
$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager list avd 2>/dev/null | grep -q "Pixel_6"
check "AVD (Pixel_6_API_34)" $?

# Builds dir writable
touch /builds/.healthcheck 2>/dev/null && rm /builds/.healthcheck
check "Builds directory writable" $?

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ $FAIL -eq 0 ]; then
  echo "✅ All checks passed — agent is healthy"
  exit 0
else
  echo "⚠️  $FAIL check(s) failed"
  exit 1
fi
