#!/bin/sh
# Patch: make time stack single source of truth (chrony-only) + intranet NTP servers
# Target: OpenWrt/Linxdot baseline (tested on 2.0.0.05-OPEN)
#
# Usage:
#   patch_time_stack.sh --ntp-server <host> [--ntp-server <host> ...] [--hide-ntpc-ui]
#
# Example:
#   ./patch_time_stack.sh --ntp-server 192.168.0.1 --ntp-server 192.168.0.2 --hide-ntpc-ui
#
set -eu

SERVERS=""
HIDE_NTPC_UI=0

while [ $# -gt 0 ]; do
  case "$1" in
    --ntp-server)
      [ $# -ge 2 ] || { echo "missing value for --ntp-server" >&2; exit 2; }
      SERVERS="$SERVERS $2"
      shift 2
      ;;
    --hide-ntpc-ui)
      HIDE_NTPC_UI=1
      shift 1
      ;;
    -h|--help)
      sed -n '1,90p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

SERVERS=$(echo "$SERVERS" | awk '{$1=$1;print}')
[ -n "$SERVERS" ] || { echo "need at least one --ntp-server" >&2; exit 2; }

TS=$(date +%Y%m%d_%H%M%S)
BKDIR="/root/backup_time_stack_$TS"
mkdir -p "$BKDIR"

for f in system chrony ntpclient; do
  [ -f "/etc/config/$f" ] && cp -a "/etc/config/$f" "$BKDIR/$f" || true
done

# --- 1) system timeserver (sysntpd) config: keep consistent but disable service later
# Reset server list to provided servers
uci -q delete system.ntp.server || true
for s in $SERVERS; do
  uci add_list system.ntp.server="$s"
done
uci set system.ntp.enabled='1'
uci set system.ntp.enable_server='0'

# --- 2) chrony config: make it authoritative
# Remove existing pool/server/peer entries and recreate as pools
# (chronyd init script reads /etc/config/chrony)

# delete all pools
while uci -q get chrony.@pool[0] >/dev/null 2>&1; do
  uci -q delete chrony.@pool[0] || break
done
# delete all servers
while uci -q get chrony.@server[0] >/dev/null 2>&1; do
  uci -q delete chrony.@server[0] || break
done
# delete all peers
while uci -q get chrony.@peer[0] >/dev/null 2>&1; do
  uci -q delete chrony.@peer[0] || break
done

for s in $SERVERS; do
  sec=$(uci add chrony pool)
  uci set chrony.$sec.hostname="$s"
  uci set chrony.$sec.maxpoll='12'
  uci set chrony.$sec.iburst='yes'
done

# Disable DHCP-derived NTP servers for determinism (can be flipped if desired)
# The section type is dhcp_ntp_server; it may exist as an unnamed section.
if uci -q get chrony.@dhcp_ntp_server[0] >/dev/null 2>&1; then
  uci set chrony.@dhcp_ntp_server[0].disabled='yes'
fi

# --- 3) ntpclient config (LuCI ntpc page)
# Keep the UI in sync even if the service is not present.
# Reset entries to provided servers.

# delete all ntpserver sections
while uci -q get ntpclient.@ntpserver[0] >/dev/null 2>&1; do
  uci -q delete ntpclient.@ntpserver[0] || break
done
for s in $SERVERS; do
  sec=$(uci add ntpclient ntpserver)
  uci set ntpclient.$sec.hostname="$s"
  uci set ntpclient.$sec.port='123'
done
# keep default interval if present
uci -q set ntpclient.@ntpclient[0].interval='600' || true

# Commit UCI changes
uci commit system
uci commit chrony
uci commit ntpclient

# --- 4) Services: enforce chrony-only
# stop+disable sysntpd (ntpd wrapper)
if [ -x /etc/init.d/sysntpd ]; then
  /etc/init.d/sysntpd stop || true
  /etc/init.d/sysntpd disable || true
fi

# enable+restart chronyd
if [ -x /etc/init.d/chronyd ]; then
  /etc/init.d/chronyd enable || true
  /etc/init.d/chronyd restart || /etc/init.d/chronyd start || true
fi

# --- 5) LuCI de-confuse: hide ntpc page/menu entry (optional)
# On baseline we verified this file exists:
#   /usr/share/luci/menu.d/luci-app-ntpc.json
# Hiding it removes the second NTP-setting place in the UI.
if [ "$HIDE_NTPC_UI" = "1" ]; then
  if [ -f /usr/share/luci/menu.d/luci-app-ntpc.json ]; then
    mv /usr/share/luci/menu.d/luci-app-ntpc.json "$BKDIR/luci-app-ntpc.json" || true
    # Best-effort reload (varies by image)
    /etc/init.d/rpcd restart 2>/dev/null || true
    /etc/init.d/uhttpd restart 2>/dev/null || true
    /etc/init.d/nginx restart 2>/dev/null || true
  fi
fi

echo "OK: patched time stack to chrony-only"
echo "- Backup: $BKDIR"
echo "- NTP servers: $SERVERS"
echo "Next checks:"
echo "  ps w | egrep 'chronyd|ntpd'"
echo "  /etc/init.d/chronyd status; /etc/init.d/sysntpd status"
