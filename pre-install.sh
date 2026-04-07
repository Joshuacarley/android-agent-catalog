#!/bin/bash
# pre-install.sh
# Run this ONCE in TrueNAS Shell before installing the app.
# It creates the required ZFS datasets.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/Joshuacarley/android-agent-catalog/main/pre-install.sh | bash
# Or paste into TrueNAS → System → Shell

POOL="${1:-tank}"
BASE="${POOL}/agent-data"

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
  zfs list "$ds" &>/dev/null && echo "  exists: $ds" || \
    (zfs create "$ds" && echo "  created: $ds")
done

# Permissions — containers run as root inside, host sees these dirs
chmod -R 777 "/mnt/$BASE/bus"
chmod 755 "/mnt/$BASE"

echo ""
echo "✅ Done. You can now install Android Agent Team from the Apps catalog."
echo "   Use /mnt/$BASE as your Data Storage Path in the install wizard."
