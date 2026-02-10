#!/bin/sh
set -eu

# verify_chrony_only_patch.sh
# Usage:
#   ./verify_chrony_only_patch.sh root@<ip>
#   SSH_OPTS='-J root@jump' ./verify_chrony_only_patch.sh root@<ip>

SSH_CMD=${SSH_CMD:-ssh}
SSH_OPTS=${SSH_OPTS:-}

TARGET=${1:-}
[ -n "$TARGET" ] || { echo "usage: $0 root@<ip>" >&2; exit 2; }

$SSH_CMD $SSH_OPTS "$TARGET" 'sh -s' <<'REMOTE'
set -eu

echo '=== services ==='
/etc/init.d/chronyd status 2>/dev/null || echo 'chronyd: (no status cmd)'
/etc/init.d/sysntpd status 2>/dev/null || true
/etc/init.d/ntpclient status 2>/dev/null || true

echo

echo '=== processes (chrony/ntp) ==='
ps w | egrep 'chronyd|ntpd|ntpclient' | grep -v grep || echo '(none)'

echo

echo '=== LuCI ntpc menu entry ==='
if [ -f /usr/share/luci/menu.d/luci-app-ntpc.json ]; then
  echo 'FAIL: luci-app-ntpc.json still present'
  ls -la /usr/share/luci/menu.d/luci-app-ntpc.json
else
  echo 'OK: luci-app-ntpc.json not present (hidden)'
fi

echo

echo '=== chrony sources (first lines) ==='
command -v chronyc >/dev/null 2>&1 && chronyc -n sources 2>/dev/null | sed -n '1,12p' || echo 'chronyc not found'
REMOTE
