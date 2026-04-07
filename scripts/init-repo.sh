#!/bin/bash
# scripts/init-repo.sh
# Called by coordinator on first run to clone the Android repo.
# Idempotent — safe to call multiple times.

source /agent/scripts/helpers.sh

BUILDS="/builds"

init_repo() {
  if [ -d "$BUILDS/.git" ]; then
    echo "✅ Repo already initialized at $BUILDS"
    git -C "$BUILDS" remote -v
    return 0
  fi

  echo "📦 Cloning $REPO into $BUILDS..."

  if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ GITHUB_TOKEN not set"
    return 1
  fi

  # Clone using token auth
  git clone \
    "https://${GITHUB_TOKEN}@github.com/${REPO}.git" \
    "$BUILDS" \
    --depth=50

  if [ $? -eq 0 ]; then
    echo "✅ Repo cloned"

    # Configure git identity for commits
    git -C "$BUILDS" config user.email "agent@t640.local"
    git -C "$BUILDS" config user.name "Claude Agent"

    # Copy CLAUDE.md if not present in repo
    if [ ! -f "$BUILDS/CLAUDE.md" ] && [ -f "/agent/config/CLAUDE.md.template" ]; then
      echo "⚠️  No CLAUDE.md found in repo — copying template"
      cp /agent/config/CLAUDE.md.template "$BUILDS/CLAUDE.md"
      echo "   Edit $BUILDS/CLAUDE.md and commit it to your repo for best results"
    fi

    telegram_message "✅ *Repo initialized*
Cloned \`${REPO}\` to build environment.
$([ ! -f "$BUILDS/CLAUDE.md" ] && echo "⚠️ No CLAUDE.md found — add one to your repo for best agent results")"
  else
    echo "❌ Clone failed"
    telegram_message "❌ *Repo clone failed*
Check GITHUB_TOKEN and GITHUB_REPO in your .env"
    return 1
  fi
}

init_repo
