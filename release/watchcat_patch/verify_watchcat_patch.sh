#!/bin/sh
set -eu

# verify_watchcat_patch.sh (customer-facing)
# Usage:
#   ./verify_watchcat_patch.sh root@<ip>
#   SSH_OPTS='-J root@jump' ./verify_watchcat_patch.sh root@<ip>

SSH_CMD=${SSH_CMD:-ssh}
SSH_OPTS=${SSH_OPTS:-}

TARGET=${1:-}
[ -n "$TARGET" ] || { echo "usage: $0 root@<ip>" >&2; exit 2; }

$SSH_CMD $SSH_OPTS "$TARGET" 'sh -s' <<'REMOTE'
set -eu

echo '=== /etc/config/watchcat ==='
cat /etc/config/watchcat || true

echo

echo '=== UCI chirpstack settings ==='
uci -q show watchcat | grep -E 'chirpstack_' || true

echo

echo '=== init.d watchcat contains service_recover? ==='
grep -n "service_recover" /etc/init.d/watchcat || true

echo

echo '=== watchcat.sh contains patch markers? ==='
grep -n "LIVING_UNIVERSE PATCH BEGIN: service_recover\|watchcat_service_recover" /usr/bin/watchcat.sh || true

echo

echo '=== running watchcat process ==='
ps w | grep -i watchcat | grep -v grep || true

echo

echo '=== LuCI watchcat UI (view) ==='
if [ -f /www/luci-static/resources/view/watchcat.js ]; then
  wc -c /www/luci-static/resources/view/watchcat.js || true
  grep -n "service_recover\|Service Recover" /www/luci-static/resources/view/watchcat.js | head -n 20 || true
else
  echo 'watchcat.js not found'
fi

echo

echo '=== docker (if present) ==='
command -v docker >/dev/null 2>&1 && docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}' | sed -n '1,25p' || echo 'docker not found'

echo

echo '=== recent watchcat logs ==='
logread 2>/dev/null | grep -i watchcat | tail -n 120 || true
REMOTE
