#!/bin/sh
set -eu

# deploy_chrony_only_patch.sh (customer-facing)
# Purpose: chrony-only + hide LuCI ntpc page (truth-only UI).
#
# Usage:
#   ./deploy_chrony_only_patch.sh
#   ./deploy_chrony_only_patch.sh <user@ip>
#   SSH_OPTS='-J root@jump' ./deploy_chrony_only_patch.sh

SSH_CMD=${SSH_CMD:-ssh}
SSH_OPTS=${SSH_OPTS:-}
DEFAULT_USER=${DEFAULT_USER:-root}

say() { echo "[deploy-chrony-only] $*"; }

die() { echo "[deploy-chrony-only] ERROR: $*" >&2; exit 1; }

TARGET=${1:-}

if [ -z "$TARGET" ]; then
  printf "Device IP (required): "
  read -r IP
  [ -n "$IP" ] || die "IP is required"

  printf "Username (default: %s): " "$DEFAULT_USER"
  read -r USER
  USER=${USER:-$DEFAULT_USER}

  TARGET="$USER@$IP"
fi

say "target=$TARGET"
[ -n "$SSH_OPTS" ] && say "SSH_OPTS=$SSH_OPTS"

$SSH_CMD $SSH_OPTS "$TARGET" 'sh -s' <<'REMOTE'
set -eu

TS=$(date +%Y%m%d_%H%M%S)
BK=/root/backup_chrony_only_patch_$TS
mkdir -p "$BK"

echo "backup=$BK"

# 1) Hide LuCI ntpc menu (remove 2nd config entry)
MENU=/usr/share/luci/menu.d/luci-app-ntpc.json
if [ -f "$MENU" ]; then
  cp -a "$MENU" "$BK/" || true
  mv "$MENU" "$BK/luci-app-ntpc.json"
  echo "OK: moved $MENU -> $BK/luci-app-ntpc.json"
else
  echo "OK: $MENU not present (already hidden or not installed)"
fi

# 2) Enforce chrony-only at service layer (do not touch server list)
if [ -x /etc/init.d/sysntpd ]; then
  /etc/init.d/sysntpd stop 2>/dev/null || true
  /etc/init.d/sysntpd disable 2>/dev/null || true
  echo "OK: sysntpd disabled"
fi

if [ -x /etc/init.d/ntpclient ]; then
  /etc/init.d/ntpclient stop 2>/dev/null || true
  /etc/init.d/ntpclient disable 2>/dev/null || true
  echo "OK: ntpclient disabled"
fi

if [ -x /etc/init.d/chronyd ]; then
  /etc/init.d/chronyd enable 2>/dev/null || true
  /etc/init.d/chronyd restart 2>/dev/null || /etc/init.d/chronyd start 2>/dev/null || true
  echo "OK: chronyd enabled+running"
else
  echo "WARN: /etc/init.d/chronyd not found"
fi

# 3) Reload LuCI web services best-effort
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
/etc/init.d/nginx restart 2>/dev/null || true

echo "DONE"
REMOTE

say "DONE"
