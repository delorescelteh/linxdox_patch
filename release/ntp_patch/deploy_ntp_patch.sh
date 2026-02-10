#!/bin/sh
set -eu

# deploy_ntp_patch.sh (customer-facing)
# Guided deploy for NTP reachability warning patch.
#
# Usage:
#   ./deploy_ntp_patch.sh
#   ./deploy_ntp_patch.sh <user@ip>
#   SSH_OPTS='-J root@jump' ./deploy_ntp_patch.sh

SSH_CMD=${SSH_CMD:-ssh}
SSH_OPTS=${SSH_OPTS:-}
DEFAULT_USER=${DEFAULT_USER:-root}

say() { echo "[deploy-ntp] $*"; }

die() { echo "[deploy-ntp] ERROR: $*" >&2; exit 1; }

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

say "NOTE: ssh will prompt for password if needed."

$SSH_CMD $SSH_OPTS "$TARGET" 'sh -s' <<'REMOTE'
set -eu

LOGIN=/usr/lib/lua/luci/view/sysauth.htm
HEALTH_BIN=/usr/bin/ntp_health.sh
INITD=/etc/init.d/ntp-health

TS=$(date +%Y%m%d_%H%M%S)
BK=/root/backup_ntp_patch_$TS
mkdir -p "$BK"

cp -a "$LOGIN" "$BK/sysauth.htm" 2>/dev/null || true
cp -a /etc/crontabs/root "$BK/" 2>/dev/null || true

# --- install ntp_health.sh
cat > /tmp/ntp_health.sh <<'EOF'
#!/bin/sh
# Write NTP reachability status based on chrony sources.
# Output files (tmpfs):
# - /tmp/ntp_health.txt         human-readable single-line summary
# - /tmp/ntp_health.unreliable  present when NTP is unreachable
# - /tmp/ntp_health.meta        key=value lines

set -eu

OUT_TXT=/tmp/ntp_health.txt
OUT_BAD=/tmp/ntp_health.unreliable
OUT_META=/tmp/ntp_health.meta

NOW_EPOCH=$(date +%s)
NOW_ISO=$(date -Iseconds 2>/dev/null || date)

RELIABLE=0
REASON="unknown"
SUMMARY="NTP status unknown"
REACHABLE_COUNT=0

if command -v chronyc >/dev/null 2>&1; then
  SOURCES=$(chronyc -n sources 2>/dev/null || true)
  REACHABLE_COUNT=$(printf "%s\n" "$SOURCES" | awk 'NR>2 && NF>0 { if ($5 != "0") c++ } END { print c+0 }')

  TRACK=$(chronyc -n tracking 2>/dev/null || true)
  LEAP=$(printf "%s\n" "$TRACK" | awk -F': *' '/^Leap status/ {print $2; exit}')
  REFID=$(printf "%s\n" "$TRACK" | awk -F': *' '/^Reference ID/ {print $2; exit}')
  STRATUM=$(printf "%s\n" "$TRACK" | awk -F': *' '/^Stratum/ {print $2; exit}')

  if [ "$REACHABLE_COUNT" -le 0 ] 2>/dev/null; then
    RELIABLE=0
    REASON="ntp_unreachable"
    SUMMARY="NTP unreachable: cannot reach any NTP server (chrony sources reach=0)"
  else
    RELIABLE=1
    REASON="ntp_reachable"
    SUMMARY="NTP reachable: sources_reachable=$REACHABLE_COUNT, leap_status=${LEAP:-?}, stratum=${STRATUM:-?}, refid=${REFID:-?}"
  fi
else
  RELIABLE=0
  REASON="chronyc_missing"
  SUMMARY="NTP unreachable: chronyc not installed"
fi

TMP=$(mktemp /tmp/ntp_health.XXXXXX)
{
  echo "time_iso=$NOW_ISO"
  echo "time_epoch=$NOW_EPOCH"
  echo "reliable=$RELIABLE"
  echo "reason=$REASON"
  echo "sources_reachable=$REACHABLE_COUNT"
} > "$TMP"
mv "$TMP" "$OUT_META"

echo "$SUMMARY" > "$OUT_TXT"

if [ "$RELIABLE" = "1" ]; then
  rm -f "$OUT_BAD"
else
  : > "$OUT_BAD"
fi
EOF

cp -a /tmp/ntp_health.sh "$HEALTH_BIN"
chmod 0755 "$HEALTH_BIN"

# --- install init.d service
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

/etc/init.d/ntp-health enable 2>/dev/null || true
/etc/init.d/ntp-health restart 2>/dev/null || /etc/init.d/ntp-health start 2>/dev/null || true

# --- patch LuCI login page
BEGIN1='<!-- BEGIN LIVING_UNIVERSE_NTP_WARNING -->'
END1='<!-- END LIVING_UNIVERSE_NTP_WARNING -->'
BEGIN2='<!-- BEGIN LIVING_UNIVERSE_NTP_RUNTIME_WARNING -->'
END2='<!-- END LIVING_UNIVERSE_NTP_RUNTIME_WARNING -->'

# Remove legacy always-on warning blocks (if present)
if [ -f "$LOGIN" ]; then
  awk -v b1="$BEGIN1" -v e1="$END1" -v b2="$BEGIN2" -v e2="$END2" '
    $0==b1 {in1=1; next}
    $0==e1 {in1=0; next}
    $0==b2 {in2=1; next}
    $0==e2 {in2=0; next}
    !(in1||in2) {print}
  ' "$LOGIN" > "$LOGIN.tmp" && mv "$LOGIN.tmp" "$LOGIN"
fi

# Insert conditional warning right after <%+header%>
awk -v b="$BEGIN2" -v e="$END2" '
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

# reload web services
/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
/etc/init.d/nginx restart 2>/dev/null || true

# run once
/usr/bin/ntp_health.sh || true

echo "OK deployed NTP warning patch; backup=$BK"
REMOTE

say "DONE"
