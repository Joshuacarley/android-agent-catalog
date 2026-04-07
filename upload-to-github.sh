#!/bin/bash
# upload-to-github.sh
# Run this on your Mac to create the repo and push everything to GitHub.
#
# Prerequisites (install if missing):
#   brew install gh git
#
# Usage:
#   bash upload-to-github.sh
#
# You'll be prompted to authenticate with GitHub once if not already logged in.

set -e

GITHUB_USER="Joshuacarley"
REPO_NAME="android-agent-catalog"
REPO_DESC="Autonomous multi-agent Android CI/CD system powered by Claude Code — TrueNAS catalog app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================================"
echo "  Android Agent Catalog → GitHub Upload"
echo "  Target: github.com/${GITHUB_USER}/${REPO_NAME}"
echo "======================================================"
echo ""

# ── Check prerequisites ───────────────────────────────────────
for cmd in git gh; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ Missing: $cmd"
    echo "   Install with: brew install $cmd"
    exit 1
  fi
done
echo "✅ git and gh found"

# ── GitHub auth ───────────────────────────────────────────────
if ! gh auth status &>/dev/null; then
  echo ""
  echo "▶ Authenticating with GitHub..."
  gh auth login --hostname github.com --web
fi
echo "✅ GitHub authenticated"

# ── Create repo if it doesn't exist ───────────────────────────
echo ""
if gh repo view "${GITHUB_USER}/${REPO_NAME}" &>/dev/null; then
  echo "ℹ️  Repo already exists: github.com/${GITHUB_USER}/${REPO_NAME}"
  read -p "   Overwrite/update it? (y/N) " -n 1 -r
  echo
  [[ $REPLY =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
else
  echo "▶ Creating repo: ${GITHUB_USER}/${REPO_NAME}..."
  gh repo create "${GITHUB_USER}/${REPO_NAME}" \
    --public \
    --description "$REPO_DESC" \
    --confirm 2>/dev/null || \
  gh repo create "${REPO_NAME}" \
    --public \
    --description "$REPO_DESC"
  echo "✅ Repo created"
fi

# ── Init git and push ─────────────────────────────────────────
echo ""
echo "▶ Initializing git..."
cd "$SCRIPT_DIR"

# Remove existing .git if present (clean slate)
rm -rf .git

git init -b main
git add .
git commit -m "feat: initial release of Android Agent Team catalog app

Multi-agent Claude Code system for autonomous Android development:
- Coordinator, Architect, Developer (×N), QA, DevOps agents
- GitHub issue → APK + test video → Telegram → PR
- TrueNAS SCALE Electric Eel catalog app with install wizard
- KVM-accelerated Android emulator with screen recording"

echo ""
echo "▶ Pushing to GitHub..."
git remote add origin "https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
git push -u origin main --force

echo ""
echo "======================================================"
echo "  ✅ Upload complete!"
echo "======================================================"
echo ""
echo "📦 Repo:    https://github.com/${GITHUB_USER}/${REPO_NAME}"
echo "⚙️  Actions: https://github.com/${GITHUB_USER}/${REPO_NAME}/actions"
echo ""
echo "GitHub Actions is now building the Docker image (~20 min)."
echo "Watch the build: https://github.com/${GITHUB_USER}/${REPO_NAME}/actions"
echo ""
echo "While that runs, do this on TrueNAS:"
echo ""
echo "  1. Open TrueNAS Shell and run:"
echo "     curl -fsSL https://raw.githubusercontent.com/${GITHUB_USER}/${REPO_NAME}/main/pre-install.sh | bash"
echo ""
echo "  2. Go to Apps → Discover Apps → Manage Catalogs → Add Catalog:"
echo "     Name:   Android Agent"
echo "     Repo:   https://github.com/${GITHUB_USER}/${REPO_NAME}"
echo "     Train:  community"
echo "     Branch: main"
echo ""
echo "  3. After the image build finishes (~20 min), search 'Android Agent'"
echo "     in the Apps catalog and click Install."
echo ""
echo "  4. Follow POST-INSTALL.md to verify everything is working."
echo ""

# ── Make GHCR package public (can't do via CLI easily, show instructions) ──
echo "⚠️  One manual step required after the image builds:"
echo "   Go to: https://github.com/${GITHUB_USER}?tab=packages"
echo "   Click android-agent → Package settings → Change visibility → Public"
echo "   (This lets TrueNAS pull the image without authentication)"
echo ""
