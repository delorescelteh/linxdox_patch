#!/bin/sh
set -eu

# Rollback using LAST_BACKUP_DIR created by apply.sh

fail() { echo "ROLLBACK_FAIL: $*" >&2; exit 1; }

BKDIR=""
if [ -f ./LAST_BACKUP_DIR ]; then
  BKDIR="$(cat ./LAST_BACKUP_DIR 2>/dev/null || true)"
fi

[ -n "$BKDIR" ] || fail "LAST_BACKUP_DIR not found; cannot determine backup dir"
[ -d "$BKDIR" ] || fail "backup dir not found: $BKDIR"

restore() {
  src="$1"
  dst="$2"
  if [ -f "$src" ]; then
    cp -a "$src" "$dst"
  fi
}

restore "$BKDIR/chrony" /etc/config/chrony
restore "$BKDIR/system" /etc/config/system
restore "$BKDIR/ntpclient" /etc/config/ntpclient

# Restore luci ntpc menu entry if it was moved away
if [ -f "$BKDIR/luci-app-ntpc.json" ]; then
  mkdir -p /usr/share/luci/menu.d 2>/dev/null || true
  cp -a "$BKDIR/luci-app-ntpc.json" /usr/share/luci/menu.d/luci-app-ntpc.json || true
fi

# Restart services (best effort)
if [ -x /etc/init.d/chronyd ]; then
  /etc/init.d/chronyd restart || true
fi
if [ -x /etc/init.d/sysntpd ]; then
  /etc/init.d/sysntpd enable || true
  /etc/init.d/sysntpd restart || true
fi

echo "ROLLBACK_OK: restored from $BKDIR"
