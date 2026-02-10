#!/bin/sh
# Verify patch_watchcat on target.
# Usage: ./verify_watchcat.sh root@<ip>
set -eu
TARGET=${1:-}
[ -n "$TARGET" ] || { echo "usage: $0 root@<ip>" >&2; exit 2; }

SSH_CMD=${SSH_CMD:-ssh}
SSH_OPTS=${SSH_OPTS:-}

$SSH_CMD $SSH_OPTS "$TARGET" 'sh -s' <<'SH'
set -eu

echo '=== UCI /etc/config/watchcat ==='
cat /etc/config/watchcat || true

echo

echo '=== rc.d enablement ==='
ls -l /etc/rc.d | grep -i watchcat || true

echo

echo '=== init.d watchcat contains service_recover? ==='
grep -n "service_recover" /etc/init.d/watchcat || true

echo

echo '=== watchcat.sh contains service_recover? ==='
grep -n "watchcat_service_recover\|service_recover" /usr/bin/watchcat.sh || true

echo

echo '=== chirpstack watch config (if present) ==='
uci -q show watchcat | grep -E 'chirpstack_' || true

echo

echo '=== running watchcat process ==='
ps w | grep -i watchcat | grep -v grep || true

echo

echo '=== recent watchcat logs ==='
logread 2>/dev/null | grep -i watchcat | tail -n 80 || true
SH
