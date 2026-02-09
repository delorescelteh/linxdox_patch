#!/bin/sh
# Apply patch_watchcat (service_recover mode) to target device.
#
# Design goals:
# - Patch the existing watchcat (UCI + init.d + /usr/bin/watchcat.sh)
# - NO external ping dependency
# - service_recover mode checks (phase-1): disk space + docker health
# - Reboot only after failure_period, and rate-limited by reboot_backoff (default 1h)
#
# BusyBox-safe: uses sh + sed + grep + head/tail + cp/mv.
#
# Usage:
#   ./apply_watchcat.sh root@<ip>

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

# --- 0) Ensure UCI has our recommended defaults
uci -q set watchcat.@watchcat[0].mode='service_recover' || true
uci -q set watchcat.@watchcat[0].period='1h' || true
uci -q set watchcat.@watchcat[0].reboot_backoff='1h' || true
uci -q set watchcat.@watchcat[0].disk_path='/' || true
uci -q set watchcat.@watchcat[0].disk_min_kb='200000' || true
uci -q set watchcat.@watchcat[0].docker_check='1' || true
uci -q commit watchcat || true

# --- 1) Patch /etc/init.d/watchcat deterministically (rewrite from known-good template embedded here)
cat > /etc/init.d/watchcat <<'INIT'
#!/bin/sh /etc/rc.common

USE_PROCD=1

START=97
STOP=01

append_string() {
	varname="$1"
	add="$2"
	separator="${3:- }"
	local actual
	eval "actual=\$$varname"

	new="${actual:+$actual$separator}$add"
	eval "$varname=\$new"
}

time_to_seconds() {
	time=$1

	{ [ "$time" -ge 1 ] 2> /dev/null && seconds="$time"; } ||
		{ [ "${time%s}" -ge 1 ] 2> /dev/null && seconds="${time%s}"; } ||
		{ [ "${time%m}" -ge 1 ] 2> /dev/null && seconds=$((${time%m} * 60)); } ||
		{ [ "${time%h}" -ge 1 ] 2> /dev/null && seconds=$((${time%h} * 3600)); } ||
		{ [ "${time%d}" -ge 1 ] 2> /dev/null && seconds=$((${time%d} * 86400)); }

	echo $seconds
	unset seconds
	unset time
}

config_watchcat() {
	# Read config
	config_get period "$1" period "120"
	config_get mode "$1" mode "ping_reboot"
	config_get pinghosts "$1" pinghosts "8.8.8.8"
	config_get pingperiod "$1" pingperiod "60"
	config_get forcedelay "$1" forcedelay "60"
	config_get pingsize "$1" pingsize "standard"
	config_get interface "$1" interface
	config_get mmifacename "$1" mmifacename
	config_get_bool unlockbands "$1" unlockbands "0"

	# New options for service_recover
	config_get reboot_backoff "$1" reboot_backoff "1h"
	config_get disk_path "$1" disk_path "/"
	config_get disk_min_kb "$1" disk_min_kb "200000"
	config_get docker_check "$1" docker_check "1"

	# Fix potential typo in mode and provide backward compatibility.
	[ "$mode" = "allways" ] && mode="periodic_reboot"
	[ "$mode" = "always" ] && mode="periodic_reboot"
	[ "$mode" = "ping" ] && mode="ping_reboot"

	# Checks for settings common to all operation modes
	if [ "$mode" != "periodic_reboot" ] && [ "$mode" != "ping_reboot" ] && [ "$mode" != "restart_iface" ] && [ "$mode" != "service_recover" ]; then
		append_string "error" "mode must be 'periodic_reboot' or 'ping_reboot' or 'restart_iface' or 'service_recover'" "; "
	fi

	period="$(time_to_seconds "$period")"
	[ "$period" -ge 1 ] ||
		append_string "error" "period has invalid format. Use time value(ex: '30'; '4m'; '6h'; '2d')" "; "

	# ping_reboot mode and restart_iface mode specific checks
	if [ "$mode" = "ping_reboot" ] || [ "$mode" = "restart_iface" ]; then
		if [ -z "$error" ]; then
			pingperiod_default="$((period / 5))"
			pingperiod="$(time_to_seconds "$pingperiod")"

			if [ "$pingperiod" -ge 0 ] && [ "$pingperiod" -ge "$period" ]; then
				pingperiod="$(time_to_seconds "$pingperiod_default")"
				append_string "warn" "pingperiod cannot be greater than $period. Defaulted to $pingperiod_default seconds (1/5 of period)" "; "
			fi

			if [ "$pingperiod" -lt 0 ]; then
				append_string "warn" "pingperiod cannot be a negative value." "; "
			fi

			if [ "$mmifacename" != "" ] && [ "$period" -lt 30 ]; then
				append_string "error" "Check interval is less than 30s. For robust operation with ModemManager modem interfaces it is recommended to set the period to at least 30s."
			fi
		fi
	fi

	# ping_reboot mode and periodic_reboot mode specific checks
	if [ "$mode" = "ping_reboot" ] || [ "$mode" = "periodic_reboot" ]; then
		forcedelay="$(time_to_seconds "$forcedelay")"
	fi

	[ -n "$warn" ] && logger -p user.warn -t "watchcat" "$1: $warn"
	[ -n "$error" ] && {
		logger -p user.err -t "watchcat" "reboot program $1 not started - $error"
		return
	}

	case "$mode" in
	periodic_reboot)
		procd_open_instance "watchcat_${1}"
		procd_set_param command /usr/bin/watchcat.sh "periodic_reboot" "$period" "$forcedelay"
		procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
		procd_close_instance
		;;
	ping_reboot)
		procd_open_instance "watchcat_${1}"
		procd_set_param command /usr/bin/watchcat.sh "ping_reboot" "$period" "$forcedelay" "$pinghosts" "$pingperiod" "$pingsize"
		procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
		procd_close_instance
		;;
	restart_iface)
		procd_open_instance "watchcat_${1}"
		procd_set_param command /usr/bin/watchcat.sh "restart_iface" "$period" "$pinghosts" "$pingperiod" "$pingsize" "$interface" "$mmifacename"
		procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
		procd_close_instance
		;;
	service_recover)
		procd_open_instance "watchcat_${1}"
		procd_set_param command /usr/bin/watchcat.sh "service_recover" "$period" "$(time_to_seconds "$reboot_backoff")" "$disk_path" "$disk_min_kb" "$docker_check"
		procd_set_param respawn ${respawn_threshold:-3600} ${respawn_timeout:-5} ${respawn_retry:-5}
		procd_close_instance
		;;
	*)
		echo "Error starting Watchcat service. Invalid mode selection: $mode"
		;;
	esac
}

start_service() {
	config_load watchcat
	config_foreach config_watchcat watchcat
}

service_triggers() {
	procd_add_reload_trigger "watchcat"
}
INIT
chmod 0755 /etc/init.d/watchcat

# --- 2) Patch /usr/bin/watchcat.sh deterministically
F=/usr/bin/watchcat.sh
TMP=/tmp/watchcat.sh.clean

# Remove any previously inserted patch blocks and the service_recover case arm (if any)
# (We'll re-add exactly one block and one case arm.)
sed -e '/LIVING_UNIVERSE PATCH BEGIN: service_recover/,/LIVING_UNIVERSE PATCH END: service_recover/d' \
    -e '/^service_recover)/,/^\t;;$/d' \
    "$F" > "$TMP"

# Append patch block AFTER shebang, BEFORE any case execution
PATCH=/tmp/watchcat_service_recover.block
cat > "$PATCH" <<'EOF'
# ---- LIVING_UNIVERSE PATCH BEGIN: service_recover ----
watchcat_service_recover() {
  failure_period="$1"
  reboot_backoff="$2"
  disk_path="$3"
  disk_min_kb="$4"
  docker_check="$5"

  stamp_file=/tmp/watchcat_last_reboot_epoch
  last_ok_file=/tmp/watchcat_last_ok_epoch

  now="$(cut -d. -f1 /proc/uptime)"
  [ "$now" -lt "$failure_period" ] && sleep "$((failure_period - now))"

  while true; do
    sleep 60

    ok=1

    if [ -n "$disk_path" ]; then
      free_kb=$(df -k "$disk_path" 2>/dev/null | awk 'NR==2{print $4}')
      if [ -n "$free_kb" ] && [ "$free_kb" -ge 0 ] 2>/dev/null; then
        if [ "$free_kb" -lt "$disk_min_kb" ]; then
          ok=0
          logger -p daemon.err -t "watchcat[$$]" "service_recover: disk_low(${disk_path} free_kb=${free_kb} < ${disk_min_kb})"
        fi
      fi
    fi

    if [ "$docker_check" = "1" ]; then
      if command -v docker >/dev/null 2>&1; then
        docker info >/dev/null 2>&1 || {
          ok=0
          logger -p daemon.err -t "watchcat[$$]" "service_recover: docker_unhealthy -> restarting dockerd"
          /etc/init.d/dockerd restart >/dev/null 2>&1 || true
        }
      else
        ok=0
        logger -p daemon.err -t "watchcat[$$]" "service_recover: docker_cli_missing"
      fi
    fi

    if [ "$ok" = "1" ]; then
      echo "$(date +%s)" > "$last_ok_file" 2>/dev/null || true
      continue
    fi

    last_ok=$(cat "$last_ok_file" 2>/dev/null || echo 0)
    now_epoch=$(date +%s)

    if [ "$last_ok" -eq 0 ] 2>/dev/null; then
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

# Build new watchcat.sh: shebang + blank + patch + rest
(head -n 1 "$TMP"; echo; cat "$PATCH"; tail -n +2 "$TMP") > /tmp/watchcat.sh.new

# Insert service_recover case arm before default "*)"
# We match a line that is exactly "*)" at line start.
sed '/^\*)/i\
service_recover)\
\twatchcat_service_recover "$2" "$3" "$4" "$5" "$6"\
\t;;\
' /tmp/watchcat.sh.new > /tmp/watchcat.sh.final

mv /tmp/watchcat.sh.final "$F"
chmod 0755 "$F"

# restart
/etc/init.d/watchcat restart || /etc/init.d/watchcat start || true

# show quick status
ubus call service list "{\"name\":\"watchcat\"}" 2>/dev/null || true
ps w | grep -E "watchcat\.sh service_recover" | grep -v grep || true

echo "OK applied patch_watchcat (service_recover)."
SH
