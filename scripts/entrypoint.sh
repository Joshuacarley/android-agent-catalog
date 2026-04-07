#!/bin/bash
# entrypoint.sh — routes each container to its role

set -e

ROLE=${1:-"worker"}
SUBROLE=${2:-""}

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
    # Subscription mode — credentials in /root/.claude (shared persistent volume)
    if [ -f "/root/.claude/.credentials.json" ]; then
      echo "✅ Claude Code: subscription credentials found"
    else
      echo ""
      echo "⚠️  Claude subscription not authenticated yet."
      echo "   Run this once after the app starts:"
      echo ""
      echo "     docker exec -it agent-coordinator claude"
      echo ""
      echo "   Log in via the browser. All containers share the"
      echo "   credentials automatically via the mounted volume."
      echo ""
      # Don't exit — container starts, user can exec in to authenticate
    fi
  fi
}

# ── GitHub CLI authentication ─────────────────────────────────
setup_github_auth() {
  if [ -n "$GITHUB_TOKEN" ]; then
    echo "$GITHUB_TOKEN" | gh auth login --with-token 2>/dev/null
    echo "✅ GitHub: authenticated"
  else
    echo "❌ GITHUB_TOKEN not set"
    exit 1
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

  dashboard)
    echo "📊 Starting status dashboard on :7842..."
    exec python3 /agent/bot/dashboard.py
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
