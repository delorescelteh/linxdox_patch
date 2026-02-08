#!/usr/bin/env bash
set -euo pipefail

# Audit-only fleet scan.
# Produces a CSV report without changing anything on devices.

usage() {
  cat <<'USAGE'
Usage:
  audit_only.sh --devices devices.txt [--user root] [--site NAME]

Output:
  report_<site>_<timestamp>.csv

Notes:
- devices.txt: one IP per line (# comments allowed)
- Requires ssh connectivity.
USAGE
}

devices=""
user="root"
site="site"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --devices) devices="$2"; shift 2;;
    --user) user="$2"; shift 2;;
    --site) site="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

[[ -z "$devices" ]] && { usage; exit 2; }

stamp=$(date +%Y%m%d_%H%M%S)
report="report_${site}_${stamp}.csv"

echo "ip,reachable_ssh,result,detail,hostname,linxdot_release,patch_version,mode,disk_root_use_pct,sysntpd,ntpd,chronyd,ntpclient,luci_ntpc" > "$report"

read_device() {
  local ip="$1"
  # minimal read-only probe
  ssh -o ConnectTimeout=8 -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$user@$ip" 'sh -lc '
'"'"'
set -e
hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || echo unknown
cat /etc/banner 2>/dev/null | head -n 6 | tr "\n" " " || true
cat /etc/linxdot_patch_version 2>/dev/null || echo ""
cat /etc/linxdot_mode 2>/dev/null || echo ""
df -P / | awk "NR==2{gsub(/%/,\"\",\$5); print \$5}" 2>/dev/null || echo ""
ps w | grep -v grep | egrep -q "sysntpd" && echo 1 || echo 0
ps w | grep -v grep | egrep -q "(^| )ntpd( |$)" && echo 1 || echo 0
ps w | grep -v grep | egrep -q "chronyd" && echo 1 || echo 0
ps w | grep -v grep | egrep -q "ntpclient" && echo 1 || echo 0
opkg list-installed 2>/dev/null | grep -q "^luci-app-ntpc" && echo 1 || echo 0
'"'"''
}

while IFS= read -r line; do
  ip=$(echo "$line" | sed 's/#.*$//' | xargs)
  [[ -z "$ip" ]] && continue

  if ! (exec 3<>/dev/tcp/$ip/22) 2>/dev/null; then
    echo "$ip,false,fail,TCP 22 unreachable,,,,,,,,,,," >> "$report"
    continue
  fi
  exec 3>&- 3<&-

  out=$(read_device "$ip" 2>&1) || {
    msg=$(echo "$out" | tail -n 1 | tr -d '\r' | sed 's/"/""/g')
    echo "$ip,true,fail,\"$msg\",,,,,,,,,,," >> "$report"
    continue
  }

  hostname=$(echo "$out" | sed -n '1p' | xargs)
  release=$(echo "$out" | sed -n '2p' | sed 's/"/""/g')
  patch_version=$(echo "$out" | sed -n '3p' | xargs)
  mode=$(echo "$out" | sed -n '4p' | xargs)
  usepct=$(echo "$out" | sed -n '5p' | xargs)
  sysntpd=$(echo "$out" | sed -n '6p' | xargs)
  ntpd=$(echo "$out" | sed -n '7p' | xargs)
  chronyd=$(echo "$out" | sed -n '8p' | xargs)
  ntpclient=$(echo "$out" | sed -n '9p' | xargs)
  lucintpc=$(echo "$out" | sed -n '10p' | xargs)

  echo "$ip,true,ok,,\"$hostname\",\"$release\",\"$patch_version\",\"$mode\",$usepct,$sysntpd,$ntpd,$chronyd,$ntpclient,$lucintpc" >> "$report"

done < "$devices"

echo "Report: $report"
