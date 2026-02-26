#!/bin/sh
set -eu

# Install LuCI chrony UI enhancements (copied from 248)

TS="$(date +%Y%m%d_%H%M%S)"
ROLLBACK_BASE="${ROLLBACK_BASE:-/opt/linxdot-backups/patch_rollbacks}"
BKDIR="$ROLLBACK_BASE/luci_chrony_timesync_ui_$TS"

mkdir -p "$BKDIR"

# Backup existing files (best effort)
cp -a /www/luci-static/resources/view/system/system.js "$BKDIR/" 2>/dev/null || true
cp -a /usr/sbin/chrony-status-update "$BKDIR/" 2>/dev/null || true
cp -a /etc/crontabs/root "$BKDIR/" 2>/dev/null || true

# Install new files
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cp -a "$SCRIPT_DIR/files/system.js.248" /www/luci-static/resources/view/system/system.js
cp -a "$SCRIPT_DIR/files/chrony-status-update.248" /usr/sbin/chrony-status-update
chmod +x /usr/sbin/chrony-status-update

# Ensure cron entry exists (avoid duplicates)
mkdir -p /etc/crontabs 2>/dev/null || true
[ -f /etc/crontabs/root ] || touch /etc/crontabs/root
if ! grep -q "chrony-status-update" /etc/crontabs/root; then
  echo "* * * * * /usr/sbin/chrony-status-update >/dev/null 2>&1" >> /etc/crontabs/root
fi

# Run once now to populate status files
/usr/sbin/chrony-status-update >/dev/null 2>&1 || true

# Restart services (best effort)
/etc/init.d/cron restart 2>/dev/null || /etc/init.d/cron reload 2>/dev/null || true
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
/etc/init.d/nginx restart 2>/dev/null || true

# Record rollback pointer
echo "$BKDIR" > ./LAST_BACKUP_DIR

echo "OK: applied luci_chrony_timesync_ui"
echo "Backup: $BKDIR"
