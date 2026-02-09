#!/bin/sh
# Apply patch_watchcat (service_recover mode) to target device.
# This patches the existing watchcat implementation:
# - /usr/bin/watchcat.sh (adds service_recover mode)
# - /etc/init.d/watchcat (allows mode + passes args)
# - /etc/config/watchcat (sets recommended defaults)
#
# Usage:
#   apply_watchcat.sh root@<ip>
# Example:
#   ./apply_watchcat.sh root@192.168.0.88

set -eu
TARGET=${1:-}
[ -n "$TARGET" ] || { echo "usage: $0 root@<ip>" >&2; exit 2; }

ssh "$TARGET" 'sh -s' <<'SH'
set -eu
TS=$(date +%Y%m%d_%H%M%S)
BK=/root/backup_watchcat_patch_$TS
mkdir -p "$BK"

cp -a /etc/config/watchcat "$BK/" 2>/dev/null || true
cp -a /etc/init.d/watchcat "$BK/" 2>/dev/null || true
cp -a /usr/bin/watchcat.sh "$BK/" 2>/dev/null || true

echo "Backup: $BK"

# 1) patch /usr/bin/watchcat.sh (append new mode if not present)
if ! grep -q "service_recover" /usr/bin/watchcat.sh; then
  cat >> /usr/bin/watchcat.sh <<'EOF'

# ---- LIVING_UNIVERSE PATCH BEGIN: service_recover ----
time_to_seconds_lu() {
  t=$1
  { [ "$t" -ge 1 ] 2>/dev/null && echo "$t" && return; } || true
  { [ "${t%s}" -ge 1 ] 2>/dev/null && echo "${t%s}" && return; } || true
  { [ "${t%m}" -ge 1 ] 2>/dev/null && echo $((${t%m} * 60)) && return; } || true
  { [ "${t%h}" -ge 1 ] 2>/dev/null && echo $((${t%h} * 3600)) && return; } || true
  { [ "${t%d}" -ge 1 ] 2>/dev/null && echo $((${t%d} * 86400)) && return; } || true
  echo "-1"
}

watchcat_service_recover() {
  failure_period="$1"          # seconds
  reboot_backoff="$2"          # seconds
  disk_path="$3"               # path to check
  disk_min_kb="$4"             # minimum free KB
  docker_check="$5"            # 0/1

  stamp_file=/tmp/watchcat_last_reboot_epoch
  last_ok_file=/tmp/watchcat_last_ok_epoch

  now="$(cut -d. -f1 /proc/uptime)"
  [ "$now" -lt "$failure_period" ] && sleep "$((failure_period - now))"

  while true; do
    # tick every 60s
    sleep 60

    ok=1
    reason=""

    # Disk check
    if [ -n "$disk_path" ]; then
      free_kb=$(df -k "$disk_path" 2>/dev/null | awk 'NR==2{print $4}')
      if [ -n "$free_kb" ] && [ "$free_kb" -ge 0 ] 2>/dev/null; then
        if [ "$free_kb" -lt "$disk_min_kb" ]; then
          ok=0
          reason="disk_low(${disk_path} free_kb=${free_kb} < ${disk_min_kb})"
          logger -p daemon.err -t "watchcat[$$]" "service_recover: $reason"
        fi
      fi
    fi

    # Docker check
    if [ "$docker_check" = "1" ]; then
      if command -v docker >/dev/null 2>&1; then
        docker info >/dev/null 2>&1 || {
          ok=0
          reason2="docker_unhealthy"
          logger -p daemon.err -t "watchcat[$$]" "service_recover: $reason2 -> restarting dockerd"
          /etc/init.d/dockerd restart >/dev/null 2>&1 || true
        }
      else
        ok=0
        logger -p daemon.err -t "watchcat[$$]" "service_recover: docker CLI missing"
      fi
    fi

    # Mark last ok
    if [ "$ok" = "1" ]; then
      echo "$(date +%s)" > "$last_ok_file" 2>/dev/null || true
      continue
    fi

    # Decide reboot if failures persist past failure_period and obey backoff
    last_ok=$(cat "$last_ok_file" 2>/dev/null || echo 0)
    now_epoch=$(date +%s)
    # If we never had ok, assume failure started at boot time
    if [ "$last_ok" -eq 0 ] 2>/dev/null; then
      # approximate: use uptime as failure duration
      fail_dur=$(cut -d. -f1 /proc/uptime)
    else
      fail_dur=$((now_epoch - last_ok))
    fi

    if [ "$fail_dur" -ge "$failure_period" ]; then
      last_reboot=$(cat "$stamp_file" 2>/dev/null || echo 0)
      since_reboot=$((now_epoch - last_reboot))
      if [ "$since_reboot" -ge "$reboot_backoff" ]; then
        logger -p daemon.err -t "watchcat[$$]" "service_recover: fail_dur=${fail_dur}s >= ${failure_period}s; rebooting (backoff=${reboot_backoff}s)"
        echo "$now_epoch" > "$stamp_file" 2>/dev/null || true
        reboot &
        exit 0
      else
        logger -p daemon.warn -t "watchcat[$$]" "service_recover: reboot suppressed by backoff (since_reboot=${since_reboot}s < ${reboot_backoff}s)"
      fi
    fi
  done
}
# ---- LIVING_UNIVERSE PATCH END: service_recover ----
EOF
fi

# 2) patch mode dispatch in watchcat.sh (add case)
if ! grep -q "service_recover" /usr/bin/watchcat.sh | grep -q "case"; then
  :
fi
# insert a case arm before default; simple append if not present
if ! grep -q "^service_recover)" /usr/bin/watchcat.sh; then
  # Use sed to add block before *)
  sed -i.bak '/^\*)/i\
service_recover)\
\twatchcat_service_recover "$2" "$3" "$4" "$5" "$6"\
\t;;\
' /usr/bin/watchcat.sh
fi

# 3) patch /etc/init.d/watchcat to allow new mode + pass args from UCI
# Minimal: extend allowed modes + pass params.

# Add mode validation
if ! grep -q "service_recover" /etc/init.d/watchcat; then
  sed -i.bak "s/periodic_reboot' or 'ping_reboot' or 'restart_iface'/periodic_reboot' or 'ping_reboot' or 'restart_iface' or 'service_recover'/" /etc/init.d/watchcat || true
  sed -i.bak "s/\[ \"\$mode\" != \"restart_iface\" \]/\[ \"\$mode\" != \"restart_iface\" \] \&\& \[ \"\$mode\" != \"service_recover\" \]/" /etc/init.d/watchcat || true
fi

# Add UCI reads + procd command for service_recover
if ! grep -q "service_recover" /etc/init.d/watchcat; then
  # add config_gets near other config_get
  sed -i.bak '/config_get_bool unlockbands/a\
\tconfig_get reboot_backoff "$1" reboot_backoff "1h"\
\tconfig_get disk_path "$1" disk_path "/"\
\tconfig_get disk_min_kb "$1" disk_min_kb "200000"\
\tconfig_get docker_check "$1" docker_check "1"\
' /etc/init.d/watchcat

  # in case statement add service_recover arm
  sed -i.bak '/restart_iface)/i\
\tservice_recover)\
\t\tprocd_open_instance "watchcat_'"'"'${1}'"'"'"\
\t\tprocd_set_param command /usr/bin/watchcat.sh "service_recover" "$period" "$(time_to_seconds \"$reboot_backoff\")" "$disk_path" "$disk_min_kb" "$docker_check"\
\t\tprocd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}\
\t\tprocd_close_instance\
\t\t;;\
' /etc/init.d/watchcat
fi

# 4) Set recommended UCI defaults (no external ping)
uci -q set watchcat.@watchcat[0].mode='service_recover' || true
uci -q set watchcat.@watchcat[0].period='1h' || true
uci -q set watchcat.@watchcat[0].reboot_backoff='1h' || true
uci -q set watchcat.@watchcat[0].disk_path='/' || true
uci -q set watchcat.@watchcat[0].disk_min_kb='200000' || true
uci -q set watchcat.@watchcat[0].docker_check='1' || true
uci -q commit watchcat || true

# restart watchcat
/etc/init.d/watchcat restart || /etc/init.d/watchcat start || true

echo "OK applied patch_watchcat (service_recover)."
SH
