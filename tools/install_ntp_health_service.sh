#!/bin/sh
# Install NTP health daemon (procd) + integrate with LuCI login page.
# - Adds /usr/bin/ntp_health.sh
# - Adds /etc/init.d/ntp-health (loop every 60s)
# - Patches /usr/lib/lua/luci/view/sysauth.htm to show warning ONLY when NOT reliable
#
# Usage:
#   install_ntp_health_service.sh
#   install_ntp_health_service.sh --remove

set -eu
REMOVE=0
[ "${1:-}" = "--remove" ] && REMOVE=1

LOGIN=/usr/lib/lua/luci/view/sysauth.htm
HEALTH_BIN=/usr/bin/ntp_health.sh
INITD=/etc/init.d/ntp-health

TS=$(date +%Y%m%d_%H%M%S)
BKDIR=/root/backup_ntp_health_$TS
mkdir -p "$BKDIR"

BEGIN='<!-- BEGIN LIVING_UNIVERSE_NTP_RUNTIME_WARNING -->'
END='<!-- END LIVING_UNIVERSE_NTP_RUNTIME_WARNING -->'

if [ "$REMOVE" = "1" ]; then
  # restore login patch block
  if [ -f "$LOGIN" ]; then
    cp -a "$LOGIN" "$BKDIR/sysauth.htm"
    awk -v b="$BEGIN" -v e="$END" '
      $0==b {inblk=1; next}
      $0==e {inblk=0; next}
      !inblk {print}
    ' "$LOGIN" > "$LOGIN.tmp" && mv "$LOGIN.tmp" "$LOGIN"
  fi

  /etc/init.d/ntp-health stop 2>/dev/null || true
  /etc/init.d/ntp-health disable 2>/dev/null || true
  [ -f "$INITD" ] && mv "$INITD" "$BKDIR/ntp-health.init" || true
  [ -f "$HEALTH_BIN" ] && mv "$HEALTH_BIN" "$BKDIR/ntp_health.sh" || true

  /etc/init.d/rpcd restart 2>/dev/null || true
  /etc/init.d/uhttpd restart 2>/dev/null || true
  /etc/init.d/nginx restart 2>/dev/null || true

  echo "OK removed ntp-health; backup=$BKDIR"
  exit 0
fi

# install health bin
cp -a "$HEALTH_BIN" "$BKDIR/" 2>/dev/null || true
install -m 0755 /tmp/ntp_health.sh "$HEALTH_BIN"

# install init.d
cat > "$INITD" <<'INIT'
#!/bin/sh /etc/rc.common
START=97
USE_PROCD=1

start_service() {
  procd_open_instance
  procd_set_param command /bin/sh -c 'while true; do /usr/bin/ntp_health.sh; sleep 60; done'
  procd_set_param respawn 3600 5 5
  procd_close_instance
}
INIT
chmod 0755 "$INITD"

# enable + start
/etc/init.d/ntp-health enable || true
/etc/init.d/ntp-health restart || /etc/init.d/ntp-health start || true

# Patch login page: show warning only if /tmp/ntp_health.unreliable exists
# (our ntp_health.sh sets /tmp/ntp_health.unreliable ONLY when it cannot reach any NTP server)
cp -a "$LOGIN" "$BKDIR/sysauth.htm" || true

# If already patched, do nothing
if ! grep -qF "$BEGIN" "$LOGIN"; then
  awk -v b="$BEGIN" -v e="$END" '
    {
      print
      if ($0 ~ /<%\+header%>/) {
        print b
        print "<% local fs = require \"nixio.fs\" %>"
        print "<% if fs.access(\"/tmp/ntp_health.unreliable\") then %>"
        print "<div class=\"alert-message warning\" style=\"margin-top: 12px;\">"
        print "  <p><strong>注意：</strong>此設備目前<strong>無法連線到任何 NTP 伺服器</strong>，系統時間可能不正確，可能造成日誌、憑證、排程、清理策略等行為不可靠並帶來風險。請設定『可到達的』NTP 伺服器（建議使用內網 NTP）。</p>"
        print "  <p><strong>Warning:</strong> This device currently <strong>cannot reach any NTP server</strong>. The system time may be incorrect and may cause risks (logs/certificates/schedules/cleanup). Please configure a reachable NTP server (preferably an intranet NTP source).</p>"
        print "  <p><strong>Status:</strong> <%=pcdata(fs.readfile(\"/tmp/ntp_health.txt\") or \"(no status)\")%></p>"
        print "</div>"
        print "<% end %>"
        print e
      }
    }
  ' "$LOGIN" > "$LOGIN.tmp" && mv "$LOGIN.tmp" "$LOGIN"
fi

# reload services
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
/etc/init.d/nginx restart 2>/dev/null || true

echo "OK installed ntp-health + conditional login warning; backup=$BKDIR"

echo "Checks:"
  echo "  cat /tmp/ntp_health.txt"
  echo "  test -f /tmp/ntp_health.unreliable && echo UNRELIABLE || echo RELIABLE"
