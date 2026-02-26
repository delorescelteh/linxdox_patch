#!/bin/sh
set -eu

fail() { echo "VERIFY_FAIL: $*" >&2; exit 1; }

[ -f /www/luci-static/resources/view/system/system.js ] || fail "missing system.js"
[ -x /usr/sbin/chrony-status-update ] || fail "missing chrony-status-update"

grep -q "chrony-status-update" /etc/crontabs/root 2>/dev/null || fail "missing cron entry"

# Run updater and check generated files
/usr/sbin/chrony-status-update >/dev/null 2>&1 || true

[ -s /var/run/chrony-status/sources.txt ] || fail "sources.txt not generated"
[ -s /var/run/chrony-status/tracking.txt ] || fail "tracking.txt not generated"
[ -s /var/run/chrony-status/updated_at.txt ] || fail "updated_at.txt not generated"

echo "VERIFY_OK"
