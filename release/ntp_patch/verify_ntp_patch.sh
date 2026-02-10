#!/bin/sh
set -eu

# verify_ntp_patch.sh (customer-facing)
# Usage:
#   ./verify_ntp_patch.sh root@<ip>
#   SSH_OPTS='-J root@jump' ./verify_ntp_patch.sh root@<ip>

SSH_CMD=${SSH_CMD:-ssh}
SSH_OPTS=${SSH_OPTS:-}

TARGET=${1:-}
[ -n "$TARGET" ] || { echo "usage: $0 root@<ip>" >&2; exit 2; }

$SSH_CMD $SSH_OPTS "$TARGET" 'sh -s' <<'REMOTE'
set -eu

echo '=== ntp-health service ==='
ls -la /etc/init.d/ntp-health 2>/dev/null || echo 'missing /etc/init.d/ntp-health'
/etc/init.d/ntp-health status 2>/dev/null || true

echo

echo '=== ntp health files ==='
ls -la /tmp/ntp_health.* 2>/dev/null || true
cat /tmp/ntp_health.txt 2>/dev/null || true
cat /tmp/ntp_health.meta 2>/dev/null || true
[ -f /tmp/ntp_health.unreliable ] && echo 'UNRELIABLE present' || echo 'UNRELIABLE absent'

echo

echo '=== chrony sources (first lines) ==='
command -v chronyc >/dev/null 2>&1 && chronyc -n sources 2>/dev/null | sed -n '1,12p' || echo 'chronyc not found'

echo

echo '=== LuCI login patch markers ==='
grep -n 'LIVING_UNIVERSE_NTP_' /usr/lib/lua/luci/view/sysauth.htm 2>/dev/null || true

# show whether conditional block exists
grep -n '/tmp/ntp_health.unreliable' /usr/lib/lua/luci/view/sysauth.htm 2>/dev/null || true
REMOTE
