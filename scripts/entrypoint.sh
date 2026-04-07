#!/bin/bash
# entrypoint.sh — routes each container to its role.
#
# Config flow:
#   - The "dashboard" role boots immediately and serves /setup on :7842
#     so the user can enter their credentials through a web form.
#   - Every other role blocks until /agent/config/config.json exists and
#     has the required keys, then exports them as env vars and proceeds.

set -e

ROLE=${1:-"worker"}
SUBROLE=${2:-""}

CONFIG=/agent/config/config.json

# ── Wait for the dashboard-written config (skipped for the dashboard itself)
wait_for_config() {
  local first=1
  while true; do
    if [ -f "$CONFIG" ] && python3 - "$CONFIG" <<'PY' 2>/dev/null
import json, sys
REQ = ("github_token","github_repo","telegram_token","telegram_chat_id")
try:
    c = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
sys.exit(0 if all(str(c.get(k,"")).strip() for k in REQ) else 1)
PY
    then
      echo "✅ Configuration loaded from $CONFIG"
      return
    fi
    if [ $first -eq 1 ]; then
      echo ""
      echo "⏳ Not configured yet."
      echo "   Open the dashboard in your browser:"
      echo "     http://<your-truenas-ip>:7842/"
      echo "   Fill in the setup form, then this container will start automatically."
      echo ""
      first=0
    fi
    sleep 10
  done
}

# ── Translate config.json → env vars expected by the rest of the scripts
load_config_into_env() {
  local exports
  exports=$(python3 - "$CONFIG" <<'PY'
import json, shlex, sys
MAPPING = {
  "github_token":        "GITHUB_TOKEN",
  "github_repo":         "GITHUB_REPO",
  "telegram_token":      "TELEGRAM_TOKEN",
  "telegram_chat_id":    "TELEGRAM_CHAT_ID",
  "anthropic_api_key":   "ANTHROPIC_API_KEY",
  "anthropic_auth_mode": "CLAUDE_AUTH_MODE",
  "issue_label":         "CLAUDE_ISSUE_LABEL",
  "poll_interval":       "POLL_INTERVAL_SECONDS",
  "developer_count":     "DEVELOPER_COUNT",
  "app_package":         "APP_PACKAGE",
  "timezone":            "TZ",
}
c = json.load(open(sys.argv[1]))
for k, envk in MAPPING.items():
    if k in c and c[k] not in (None, ""):
        print(f"export {envk}={shlex.quote(str(c[k]))}")
PY
  )
  eval "$exports"
}

# ── Claude Code authentication ────────────────────────────────
setup_claude_auth() {
  local mode="${CLAUDE_AUTH_MODE:-subscription}"

  if [ "$mode" = "api_key" ]; then
    if [ -z "$ANTHROPIC_API_KEY" ]; then
      echo "❌ CLAUDE_AUTH_MODE=api_key but ANTHROPIC_API_KEY is not set."
      exit 1
    fi
    echo "✅ Claude Code: using API key"
  else
    if [ -f "/root/.claude/.credentials.json" ]; then
      echo "✅ Claude Code: subscription credentials found"
    else
      echo ""
      echo "⚠️  Claude subscription not authenticated yet."
      echo "   Run this once after the app starts:"
      echo ""
      echo "     sudo docker exec -it agent-coordinator claude"
      echo ""
      echo "   Log in via the browser. All containers share the"
      echo "   credentials automatically via the mounted volume."
      echo ""
    fi
  fi
}

# ── GitHub CLI authentication ─────────────────────────────────
setup_github_auth() {
  if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ GITHUB_TOKEN not set (shouldn't happen after wait_for_config)"
    exit 1
  fi

  # Ensure gh has a writable config dir
  export GH_CONFIG_DIR="${GH_CONFIG_DIR:-/root/.config/gh}"
  mkdir -p "$GH_CONFIG_DIR"

  # Don't let gh failure kill the whole container — surface the error
  # and fall back to the GH_TOKEN env var (which gh honors directly).
  if echo "$GITHUB_TOKEN" | gh auth login --with-token; then
    echo "✅ GitHub: authenticated via gh auth login"
  else
    echo "⚠️  gh auth login failed — falling back to GH_TOKEN env var"
    export GH_TOKEN="$GITHUB_TOKEN"
  fi
}

# ── Ensure bus directories exist ──────────────────────────────
setup_bus() {
  mkdir -p \
    /agent/bus/queue \
    /agent/bus/in-progress \
    /agent/bus/done \
    /agent/bus/messages \
    /agent/workspaces \
    /agent/logs
}

# ── Dashboard: boot immediately, no config required ──────────
if [ "$ROLE" = "dashboard" ]; then
  setup_bus
  echo "📊 Starting status dashboard on :7842..."
  echo "   First-time setup: http://<your-truenas-ip>:7842/setup"
  exec python3 /agent/bot/dashboard.py
fi

# ── All other roles: wait for web-UI config, then load & run ─
wait_for_config
load_config_into_env
setup_github_auth
setup_claude_auth
setup_bus

# Init repo on coordinator and devops containers
if [[ "$ROLE" == "coordinator" || ( "$ROLE" == "worker" && "$SUBROLE" == "devops" ) ]]; then
  /agent/scripts/init-repo.sh
fi

case "$ROLE" in
  telegram-bot)
    echo "🤖 Starting Telegram bot..."
    exec python3 /agent/bot/bot.py
    ;;

  coordinator)
    echo "📋 Starting coordinator (cron mode)..."
    exec /agent/scripts/coordinator-cron.sh
    ;;

  worker)
    echo "⚙️  Starting worker: $SUBROLE"
    exec /agent/scripts/worker.sh "$SUBROLE"
    ;;

  *)
    echo "Unknown role: $ROLE"
    exit 1
    ;;
esac
