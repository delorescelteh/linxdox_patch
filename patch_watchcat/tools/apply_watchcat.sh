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

SSH_CMD=${SSH_CMD:-ssh}
SSH_OPTS=${SSH_OPTS:-}

$SSH_CMD $SSH_OPTS "$TARGET" 'sh -s' <<'SH'
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
# Conservative disk cleanup (only removes patch-generated backups under /root)
uci -q set watchcat.@watchcat[0].disk_cleanup_enable='1' || true
uci -q set watchcat.@watchcat[0].disk_cleanup_keep='3' || true

# ChirpStack stack check + recovery
uci -q set watchcat.@watchcat[0].chirpstack_check='1' || true
uci -q set watchcat.@watchcat[0].chirpstack_compose_dir='/mnt/opensource-system/chirpstack-docker' || true
# Recovery strategy:
# - docker_restart_then_compose: try docker restart for failed containers, then compose up -d
uci -q set watchcat.@watchcat[0].chirpstack_recover='docker_restart_then_compose' || true
uci -q set watchcat.@watchcat[0].chirpstack_recover_cooldown='300' || true
# Prefer prefix/substr-based matching to avoid compose project/index changes
uci -q set watchcat.@watchcat[0].chirpstack_name_prefix='chirpstack-docker_' || true
# Required components (substring match against running container names under prefix)
uci -q delete watchcat.@watchcat[0].chirpstack_required 2>/dev/null || true
uci -q add_list watchcat.@watchcat[0].chirpstack_required='chirpstack-rest-api' || true
uci -q add_list watchcat.@watchcat[0].chirpstack_required='chirpstack-gateway-bridge' || true
uci -q add_list watchcat.@watchcat[0].chirpstack_required='chirpstack' || true
uci -q add_list watchcat.@watchcat[0].chirpstack_required='postgres' || true
uci -q add_list watchcat.@watchcat[0].chirpstack_required='mosquitto' || true
uci -q add_list watchcat.@watchcat[0].chirpstack_required='redis' || true

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
	config_get disk_cleanup_enable "$1" disk_cleanup_enable "1"
	config_get disk_cleanup_keep "$1" disk_cleanup_keep "3"

	# ChirpStack stack check + recovery
	config_get chirpstack_check "$1" chirpstack_check "0"
	config_get chirpstack_compose_dir "$1" chirpstack_compose_dir "/mnt/opensource-system/chirpstack-docker"
	config_get chirpstack_recover "$1" chirpstack_recover "docker_restart_then_compose"
	config_get chirpstack_recover_cooldown "$1" chirpstack_recover_cooldown "300"
	config_get chirpstack_name_prefix "$1" chirpstack_name_prefix "chirpstack-docker_"
	config_get chirpstack_required "$1" chirpstack_required ""

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
		procd_set_param command /usr/bin/watchcat.sh "service_recover" \
		"$period" "$(time_to_seconds "$reboot_backoff")" \
		"$disk_path" "$disk_min_kb" "$docker_check" "$disk_cleanup_enable" "$disk_cleanup_keep" \
		"$chirpstack_check" "$chirpstack_compose_dir" "$chirpstack_recover" "$chirpstack_recover_cooldown" "$chirpstack_name_prefix" "$chirpstack_required"
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
  disk_cleanup_enable="$6"
  disk_cleanup_keep="$7"
  chirpstack_check="$8"
  chirpstack_compose_dir="$9"
  chirpstack_recover="${10}"
  chirpstack_recover_cooldown="${11}"
  chirpstack_name_prefix="${12}"
  chirpstack_required="${13}"

  stamp_file=/tmp/watchcat_last_reboot_epoch
  last_ok_file=/tmp/watchcat_last_ok_epoch
  chirp_recover_stamp=/tmp/watchcat_last_chirpstack_recover_epoch
  disk_cleanup_stamp=/tmp/watchcat_last_disk_cleanup_epoch

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

          # Conservative cleanup: only remove older patch-generated backups under /root
          # Keep last N (disk_cleanup_keep) for each known pattern.
          if [ "$disk_cleanup_enable" = "1" ]; then
            now_epoch=$(date +%s)
            last_clean=$(cat "$disk_cleanup_stamp" 2>/dev/null || echo 0)
            # run at most once per 10 minutes
            if [ $((now_epoch - last_clean)) -ge 600 ] 2>/dev/null; then
              echo "$now_epoch" > "$disk_cleanup_stamp" 2>/dev/null || true

              keep="${disk_cleanup_keep:-3}"
              for pat in \
                /root/backup_watchcat_patch_* \
                /root/backup_watchcat_luci_js_* \
                /root/backup_time_stack_* \
                /root/backup_luci_login_notice_* \
                /root/backup_docker_* \
                /root/backup_*_patch_* \
              ; do
                # shellcheck disable=SC2046
                ls -dt $pat 2>/dev/null | tail -n +$((keep + 1)) | while read -r p; do
                  ts=$(date -Iseconds 2>/dev/null || date)
                  echo "$ts removing $p" >> /tmp/watchcat_disk_cleanup_last.txt 2>/dev/null || true
                  logger -p daemon.warn -t "watchcat[$$]" "service_recover: disk_cleanup removing $p"
                  rm -rf "$p" 2>/dev/null || true
                done
              done
            fi
          fi
        fi
      fi
    fi

    # ChirpStack stack check (containers)
    if [ "$chirpstack_check" = "1" ]; then
      if command -v docker >/dev/null 2>&1; then
        # Build running container name list under prefix
        running_names=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "^${chirpstack_name_prefix}" || true)

        missing=""
        for req in $chirpstack_required; do
          echo "$running_names" | grep -q "$req" || missing="$missing $req"
        done
        missing=$(echo "$missing" | awk '{$1=$1;print}')

        if [ -z "$running_names" ]; then
          ok=0
          logger -p daemon.err -t "watchcat[$$]" "service_recover: chirpstack_unhealthy no containers with prefix=${chirpstack_name_prefix}"
        elif [ -n "$missing" ]; then
          ok=0
          logger -p daemon.err -t "watchcat[$$]" "service_recover: chirpstack_unhealthy missing_components=[$missing] prefix=${chirpstack_name_prefix}"
        fi

        if [ "$ok" = "0" ]; then

          # Try recover chirpstack stack (rate-limited)
          now_epoch=$(date +%s)
          last_try=$(cat "$chirp_recover_stamp" 2>/dev/null || echo 0)
          since=$((now_epoch - last_try))
          if [ "$since" -ge "$chirpstack_recover_cooldown" ] 2>/dev/null; then
            echo "$now_epoch" > "$chirp_recover_stamp" 2>/dev/null || true

            # choose compose command
            if command -v docker-compose >/dev/null 2>&1; then
              CCMD="docker-compose"
            elif docker compose version >/dev/null 2>&1; then
              CCMD="docker compose"
            else
              CCMD=""
            fi

            if [ "$chirpstack_recover" = "docker_restart_then_compose" ]; then
              # Restart any non-running containers under prefix (best-effort)
              all_names=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E "^${chirpstack_name_prefix}" || true)
              for n in $all_names; do
                st=$(docker inspect -f '{{.State.Status}}' "$n" 2>/dev/null || echo "missing")
                if [ "$st" != "running" ] && [ "$st" != "missing" ]; then
                  logger -p daemon.err -t "watchcat[$$]" "service_recover: trying chirpstack recover via docker restart $n (status=$st)"
                  docker restart "$n" >/dev/null 2>&1 || true
                fi
              done
              # Then reconcile using compose
              if [ -n "$CCMD" ] && [ -d "$chirpstack_compose_dir" ]; then
                logger -p daemon.err -t "watchcat[$$]" "service_recover: chirpstack recover via compose up -d (dir=$chirpstack_compose_dir)"
                ( cd "$chirpstack_compose_dir" && $CCMD up -d --remove-orphans ) >/dev/null 2>&1 || true
              fi
            elif [ "$chirpstack_recover" = "compose_up" ]; then
              if [ -n "$CCMD" ] && [ -d "$chirpstack_compose_dir" ]; then
                logger -p daemon.err -t "watchcat[$$]" "service_recover: chirpstack recover via compose up -d (dir=$chirpstack_compose_dir)"
                ( cd "$chirpstack_compose_dir" && $CCMD up -d --remove-orphans ) >/dev/null 2>&1 || true
              fi
            fi
          else
            logger -p daemon.warn -t "watchcat[$$]" "service_recover: chirpstack recover suppressed by cooldown (since=${since}s < ${chirpstack_recover_cooldown}s)"
          fi
        fi
      else
        ok=0
        logger -p daemon.err -t "watchcat[$$]" "service_recover: docker_cli_missing (cannot check chirpstack containers)"
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
\twatchcat_service_recover "$2" "$3" "$4" "$5" "$6" "$7" "${8}" "${9}" "${10}" "${11}" "${12}" "${13}"\
\t;;\
' /tmp/watchcat.sh.new > /tmp/watchcat.sh.final

# Remove any duplicate watchcat_service_recover() definitions that may still exist
# Keep the first one (the injected block near the top) and drop subsequent ones up to their end marker.
awk '
  /^watchcat_service_recover\(\)/ {
    seen++
    if (seen >= 2) { skip=1; next }
  }
  skip && /LIVING_UNIVERSE PATCH END: service_recover/ { skip=0; next }
  skip { next }
  { print }
' /tmp/watchcat.sh.final > /tmp/watchcat.sh.final2

mv /tmp/watchcat.sh.final2 "$F"
chmod 0755 "$F"

# restart
/etc/init.d/watchcat restart || /etc/init.d/watchcat start || true

# show quick status
ubus call service list "{\"name\":\"watchcat\"}" 2>/dev/null || true
ps w | grep -E "watchcat\.sh service_recover" | grep -v grep || true

echo "OK applied patch_watchcat (service_recover)."
SH
