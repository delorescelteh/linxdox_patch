#!/bin/sh
set -eu

fail() { echo "ROLLBACK_FAIL: $*" >&2; exit 1; }

BKDIR=""
[ -f ./LAST_BACKUP_DIR ] && BKDIR="$(cat ./LAST_BACKUP_DIR 2>/dev/null || true)"
[ -n "$BKDIR" ] || fail "LAST_BACKUP_DIR not found"
[ -d "$BKDIR" ] || fail "backup dir not found: $BKDIR"

# Restore files if present
if [ -f "$BKDIR/system.js" ]; then
  cp -a "$BKDIR/system.js" /www/luci-static/resources/view/system/system.js
fi
if [ -f "$BKDIR/chrony-status-update" ]; then
  cp -a "$BKDIR/chrony-status-update" /usr/sbin/chrony-status-update
  chmod +x /usr/sbin/chrony-status-update 2>/dev/null || true
fi
if [ -f "$BKDIR/root" ]; then
  cp -a "$BKDIR/root" /etc/crontabs/root
fi

# Restart services (best effort)
/etc/init.d/cron restart 2>/dev/null || /etc/init.d/cron reload 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
/etc/init.d/nginx restart 2>/dev/null || true

echo "ROLLBACK_OK: restored from $BKDIR"
