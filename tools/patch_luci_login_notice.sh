#!/bin/sh
# Patch: add NTP reliability warning to LuCI login page (bilingual zh-TW + English)
# Target file: /usr/lib/lua/luci/view/sysauth.htm
#
# Why: In offline/intranet deployments, without reachable NTP the system time may be wrong.
# This can cause risks (logs/certificates/retention/cleanup scripts). We must warn users.
#
# Usage:
#   patch_luci_login_notice.sh [--remove]
#
set -eu

REMOVE=0
[ "${1:-}" = "--remove" ] && REMOVE=1

FILE=/usr/lib/lua/luci/view/sysauth.htm
[ -f "$FILE" ] || { echo "missing: $FILE" >&2; exit 1; }

TS=$(date +%Y%m%d_%H%M%S)
BKDIR=/root/backup_luci_login_notice_$TS
mkdir -p "$BKDIR"
cp -a "$FILE" "$BKDIR/sysauth.htm"

BEGIN='<!-- BEGIN LIVING_UNIVERSE_NTP_WARNING -->'
END='<!-- END LIVING_UNIVERSE_NTP_WARNING -->'

if [ "$REMOVE" = "1" ]; then
  # Remove block if present
  awk -v b="$BEGIN" -v e="$END" '
    $0==b {inblk=1; next}
    $0==e {inblk=0; next}
    !inblk {print}
  ' "$FILE" > "$FILE.tmp"
  mv "$FILE.tmp" "$FILE"
  echo "OK: removed login notice; backup=$BKDIR"
  exit 0
fi

# If already present, do nothing
if grep -qF "$BEGIN" "$FILE"; then
  echo "OK: notice already present; backup=$BKDIR"
  exit 0
fi

# Insert right after <%+header%>
awk -v b="$BEGIN" -v e="$END" '
  {
    print
    if ($0 ~ /<%\+header%>/) {
      print b
      print "<div class=\"alert-message warning\" style=\"margin-top: 12px;\">"
      print "  <p><strong>注意：</strong>若此設備未設定可連線的 NTP 伺服器或無法連線到 NTP，系統時間可能不正確，造成日誌、憑證、排程、清理策略等行為不可靠，並帶來風險。請務必設定『可到達的』NTP 伺服器（建議使用內網 NTP）。</p>"
      print "  <p><strong>Warning:</strong> If this device is not configured with a reachable NTP server (or cannot reach NTP), the system time may be incorrect. This can make logs, certificates, schedules, and cleanup/retention behavior unreliable and may introduce risk. Please configure a reachable NTP server (preferably an intranet NTP source).</p>"
      print "</div>"
      print e
    }
  }
' "$FILE" > "$FILE.tmp"

mv "$FILE.tmp" "$FILE"

echo "OK: added LuCI login NTP warning; backup=$BKDIR"
