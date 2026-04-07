#!/bin/bash
# pre-install.sh
# Run this ONCE in TrueNAS Shell before installing the app.
# It creates the required ZFS datasets.
#
# Usage (default pool "tank"):
#   curl -fsSL https://raw.githubusercontent.com/Joshuacarley/android-agent-catalog/main/pre-install.sh | sudo bash
#
# Usage (custom pool, e.g. "mypool"):
#   curl -fsSL https://raw.githubusercontent.com/Joshuacarley/android-agent-catalog/main/pre-install.sh | sudo bash -s mypool
#
# Or paste into TrueNAS → System → Shell (already root there).

set -euo pipefail

# Make sure sbin is on PATH — zfs lives in /usr/sbin on TrueNAS SCALE.
export PATH="/usr/sbin:/sbin:/usr/local/sbin:$PATH"

# Re-exec under sudo if we are not root.
if [ "$(id -u)" -ne 0 ]; then
  echo "Not running as root — re-executing with sudo..."
  exec sudo -E bash "$0" "$@"
fi

POOL="${1:-tank}"
BASE="${POOL}/agent-data"

# Sanity check: does the pool exist?
if ! zpool list -H -o name | grep -qx "$POOL"; then
  echo "❌ ZFS pool '$POOL' not found. Available pools:"
  zpool list -H -o name | sed 's/^/   - /'
  echo ""
  echo "Re-run with your pool name, e.g.:"
  echo "  curl -fsSL https://raw.githubusercontent.com/Joshuacarley/android-agent-catalog/main/pre-install.sh | sudo bash -s <pool-name>"
  exit 1
fi

echo "Creating datasets under $BASE ..."

for ds in \
  "$BASE" \
  "$BASE/bus" \
  "$BASE/bus/queue" \
  "$BASE/bus/in-progress" \
  "$BASE/bus/done" \
  "$BASE/bus/messages" \
  "$BASE/workspaces" \
  "$BASE/logs" \
  "$BASE/builds" \
  "$BASE/android-home" \
  "$BASE/claude-credentials" \
  "$BASE/agent-config"
do
  if zfs list "$ds" &>/dev/null; then
    echo "  exists:  $ds"
  else
    zfs create -p "$ds"
    echo "  created: $ds"
  fi
done

# Permissions — containers run as root inside, host sees these dirs
chmod 755 "/mnt/$BASE"
chmod -R 777 "/mnt/$BASE/bus"

echo ""
echo "✅ Done. You can now install Android Agent Team from the Apps catalog."
echo "   Use /mnt/$BASE as your Data Storage Path in the install wizard."
