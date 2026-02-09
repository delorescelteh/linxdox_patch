#!/bin/sh
set -eu

# deploy_watchcat_patch.sh (customer-facing)
# One command deploy with guided prompts.
#
# Usage:
#   ./deploy_watchcat_patch.sh
#   ./deploy_watchcat_patch.sh <user@ip>
#   SSH_OPTS='-J root@jump' ./deploy_watchcat_patch.sh
#
# Defaults:
# - username: root
# - (ssh will prompt for password; many devices default password is: linxdot)

SSH_CMD=${SSH_CMD:-ssh}
SSH_OPTS=${SSH_OPTS:-}

DEFAULT_USER=${DEFAULT_USER:-root}
DEFAULT_PREFIX=${DEFAULT_PREFIX:-chirpstack-docker_}
DEFAULT_REQUIRED=${DEFAULT_REQUIRED:-"chirpstack chirpstack-gateway-bridge chirpstack-rest-api postgres mosquitto redis"}
DEFAULT_COMPOSE_DIR=${DEFAULT_COMPOSE_DIR:-/mnt/opensource-system/chirpstack-docker}

DEFAULT_PERIOD=${DEFAULT_PERIOD:-1h}
DEFAULT_REBOOT_BACKOFF=${DEFAULT_REBOOT_BACKOFF:-1h}
DEFAULT_DISK_PATH=${DEFAULT_DISK_PATH:-/}
DEFAULT_DISK_MIN_KB=${DEFAULT_DISK_MIN_KB:-200000}
DEFAULT_DOCKER_CHECK=${DEFAULT_DOCKER_CHECK:-1}
DEFAULT_CHIRPSTACK_CHECK=${DEFAULT_CHIRPSTACK_CHECK:-1}
DEFAULT_RECOVER=${DEFAULT_RECOVER:-docker_restart_then_compose}
DEFAULT_RECOVER_COOLDOWN=${DEFAULT_RECOVER_COOLDOWN:-300}

say() { echo "[deploy] $*"; }

die() { echo "[deploy] ERROR: $*" >&2; exit 1; }

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

say "NOTE: ssh will prompt for password if needed (often default is 'linxdot')."

$SSH_CMD $SSH_OPTS "$TARGET" 'sh -s' <<'REMOTE'
set -eu

TS=$(date +%Y%m%d_%H%M%S)
BK=/root/backup_watchcat_patch_$TS
mkdir -p "$BK"

cp -a /etc/config/watchcat "$BK/" 2>/dev/null || true
cp -a /etc/init.d/watchcat "$BK/" 2>/dev/null || true
cp -a /usr/bin/watchcat.sh "$BK/" 2>/dev/null || true

echo "Backup: $BK"

# --- Defaults (can be overridden by exporting env vars before running ssh)
PERIOD="${PERIOD:-1h}"
REBOOT_BACKOFF="${REBOOT_BACKOFF:-1h}"
DISK_PATH="${DISK_PATH:-/}"
DISK_MIN_KB="${DISK_MIN_KB:-200000}"
DOCKER_CHECK="${DOCKER_CHECK:-1}"

CHIRPSTACK_CHECK="${CHIRPSTACK_CHECK:-1}"
CHIRPSTACK_COMPOSE_DIR="${CHIRPSTACK_COMPOSE_DIR:-/mnt/opensource-system/chirpstack-docker}"
CHIRPSTACK_RECOVER="${CHIRPSTACK_RECOVER:-docker_restart_then_compose}"
CHIRPSTACK_RECOVER_COOLDOWN="${CHIRPSTACK_RECOVER_COOLDOWN:-300}"
CHIRPSTACK_NAME_PREFIX="${CHIRPSTACK_NAME_PREFIX:-chirpstack-docker_}"
CHIRPSTACK_REQUIRED="${CHIRPSTACK_REQUIRED:-chirpstack chirpstack-gateway-bridge chirpstack-rest-api postgres mosquitto redis}"

# --- 0) UCI defaults
uci -q set watchcat.@watchcat[0].mode='service_recover' || true
uci -q set watchcat.@watchcat[0].period="$PERIOD" || true
uci -q set watchcat.@watchcat[0].reboot_backoff="$REBOOT_BACKOFF" || true
uci -q set watchcat.@watchcat[0].disk_path="$DISK_PATH" || true
uci -q set watchcat.@watchcat[0].disk_min_kb="$DISK_MIN_KB" || true
uci -q set watchcat.@watchcat[0].docker_check="$DOCKER_CHECK" || true
uci -q set watchcat.@watchcat[0].disk_cleanup_enable='1' || true
uci -q set watchcat.@watchcat[0].disk_cleanup_keep='3' || true

uci -q set watchcat.@watchcat[0].chirpstack_check="$CHIRPSTACK_CHECK" || true
uci -q set watchcat.@watchcat[0].chirpstack_compose_dir="$CHIRPSTACK_COMPOSE_DIR" || true
uci -q set watchcat.@watchcat[0].chirpstack_recover="$CHIRPSTACK_RECOVER" || true
uci -q set watchcat.@watchcat[0].chirpstack_recover_cooldown="$CHIRPSTACK_RECOVER_COOLDOWN" || true
uci -q set watchcat.@watchcat[0].chirpstack_name_prefix="$CHIRPSTACK_NAME_PREFIX" || true

# replace list
uci -q delete watchcat.@watchcat[0].chirpstack_required 2>/dev/null || true
for req in $CHIRPSTACK_REQUIRED; do
  uci -q add_list watchcat.@watchcat[0].chirpstack_required="$req" || true
done

uci -q commit watchcat || true

# --- 1) rewrite /etc/init.d/watchcat (template)
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

sed -e '/LIVING_UNIVERSE PATCH BEGIN: service_recover/,/LIVING_UNIVERSE PATCH END: service_recover/d' \
    -e '/^service_recover)/,/^\t;;$/d' \
    "$F" > "$TMP"

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
          if [ "$disk_cleanup_enable" = "1" ]; then
            now_epoch=$(date +%s)
            last_clean=$(cat "$disk_cleanup_stamp" 2>/dev/null || echo 0)
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

    # ChirpStack stack check (prefix + required components)
    if [ "$chirpstack_check" = "1" ]; then
      if command -v docker >/dev/null 2>&1; then
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
          now_epoch=$(date +%s)
          last_try=$(cat "$chirp_recover_stamp" 2>/dev/null || echo 0)
          since=$((now_epoch - last_try))
          if [ "$since" -ge "$chirpstack_recover_cooldown" ] 2>/dev/null; then
            echo "$now_epoch" > "$chirp_recover_stamp" 2>/dev/null || true

            if command -v docker-compose >/dev/null 2>&1; then
              CCMD="docker-compose"
            elif docker compose version >/dev/null 2>&1; then
              CCMD="docker compose"
            else
              CCMD=""
            fi

            if [ "$chirpstack_recover" = "docker_restart_then_compose" ]; then
              all_names=$(docker ps -a --format '{{.Names}}' 2>/dev/null | grep -E "^${chirpstack_name_prefix}" || true)
              for n in $all_names; do
                st=$(docker inspect -f '{{.State.Status}}' "$n" 2>/dev/null || echo "missing")
                if [ "$st" != "running" ] && [ "$st" != "missing" ]; then
                  logger -p daemon.err -t "watchcat[$$]" "service_recover: trying chirpstack recover via docker restart $n (status=$st)"
                  docker restart "$n" >/dev/null 2>&1 || true
                fi
              done
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

(head -n 1 "$TMP"; echo; cat "$PATCH"; tail -n +2 "$TMP") > /tmp/watchcat.sh.new

# Insert service_recover case arm before default "*)" using awk (BusyBox-compatible)
awk '
  BEGIN { inserted=0 }
  /^\*\)/ && inserted==0 {
    print "service_recover)"
    print "\twatchcat_service_recover \"$2\" \"$3\" \"$4\" \"$5\" \"$6\" \"$7\" \"${8}\" \"${9}\" \"${10}\" \"${11}\" \"${12}\" \"${13}\""
    print "\t;;"
    inserted=1
  }
  { print }
' /tmp/watchcat.sh.new > /tmp/watchcat.sh.final

# Remove any duplicate watchcat_service_recover() definitions that may still exist
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

# --- 3) Patch LuCI UI to support service_recover (so UI reflects truth)
# Target: /www/luci-static/resources/view/watchcat.js
if [ -f /www/luci-static/resources/view/watchcat.js ]; then
  cp -a /www/luci-static/resources/view/watchcat.js "$BK/luci_watchcat.js" 2>/dev/null || true
  cat > /www/luci-static/resources/view/watchcat.js <<'LUCIFS'
'use strict';

'require view';
'require form';
'require tools.widgets as widgets';

return view.extend({
	render: function() {
		var m, s, o;

		m = new form.Map('watchcat', _('Watchcat（看門狗）'), _(
			'設定當主機不可達或本機服務不健康時的檢查與動作（Configure checks and actions when a host is unreachable or local services are unhealthy）。'
		));

		s = m.section(form.TypedSection, 'watchcat', _('Watchcat（看門狗）'), _(
			'這些規則定義設備對網路/服務事件的反應方式（These rules govern how this device reacts to network/service events）。'
		));
		s.anonymous = true;
		s.addremove = true;
		s.tab('general', _('一般設定（General Settings）'));

		o = s.taboption('general', form.ListValue, 'mode', _('模式（Mode）'), _(
			"Ping Reboot（Ping 重啟）：若對指定主機 ping 失敗持續一段時間，則重啟設備。 <br />" +
			"Periodic Reboot（週期性重啟）：每隔指定時間重啟設備。 <br />" +
			"Restart Interface（重啟介面）：若對指定主機 ping 失敗持續一段時間，則重啟指定網路介面。 <br />" +
			"Service Recover（服務恢復）：監控本機服務（例如 Docker/ChirpStack），優先嘗試修復，必要時才 reboot。"
		));
		o.value('ping_reboot', _('Ping Reboot（Ping 重啟）'));
		o.value('periodic_reboot', _('Periodic Reboot（週期性重啟）'));
		o.value('restart_iface', _('Restart Interface（重啟介面）'));
		o.value('service_recover', _('Service Recover（服務恢復）'));

		o = s.taboption('general', form.Value, 'period', _('週期（Period）'), _(
			"Periodic Reboot：定義多久重啟一次。 <br />" +
			"Ping Reboot：定義 Host 多久沒回應才會觸發重啟。 <br />" +
			"Restart Interface：定義 Host 多久沒回應才會重啟介面。 <br />" +
			"Service Recover：系統不健康持續多久後才允許 reboot（避免短暫抖動就重啟）。 <br /><br />" +
			"預設單位為秒（不加尾綴），也可用 m（分鐘）/ h（小時）/ d（天）。（Default unit is seconds; supports m/h/d suffixes.）"
		));
		o.default = '6h';

		/* Ping-based options */
		o = s.taboption('general', form.Value, 'pinghosts', _('要檢查的主機（Host To Check）'), _('要 ping 的 IPv4/主機名（IPv4 address or hostname to ping）。'));
		o.datatype = 'host(1)';
		o.default = '8.8.8.8';
		o.depends({ mode: 'ping_reboot' });
		o.depends({ mode: 'restart_iface' });

		o = s.taboption('general', form.Value, 'pingperiod', _('檢查間隔（Check Interval）'), _(
			'多久 ping 一次上方指定主機；可用秒或 m/h/d 尾綴（How often to ping; supports seconds or m/h/d suffixes）。'
		));
		o.default = '30s';
		o.depends({ mode: 'ping_reboot' });
		o.depends({ mode: 'restart_iface' });

		o = s.taboption('general', form.ListValue, 'pingsize', _('Ping Packet Size（封包大小）'));
		o.value('small', _('Small（小）：1 byte'));
		o.value('windows', _('Windows（Windows）：32 bytes'));
		o.value('standard', _('Standard（標準）：56 bytes'));
		o.value('big', _('Big（大）：248 bytes'));
		o.value('huge', _('Huge（超大）：1492 bytes'));
		o.value('jumbo', _('Jumbo（巨量）：9000 bytes'));
		o.default = 'standard';
		o.depends({ mode: 'ping_reboot' });
		o.depends({ mode: 'restart_iface' });

		o = s.taboption('general', form.Value, 'forcedelay', _('Force Reboot Delay（強制重啟延遲）'), _(
			'適用於 Ping Reboot / Periodic Reboot。輸入秒數：若 soft reboot 失敗，將延遲後觸發 hard reboot；0 表示停用。（Applies to Ping/Periodic reboot; delayed hard reboot if soft reboot fails; 0 disables.）'
		));
		o.default = '1m';
		o.depends({ mode: 'ping_reboot' });
		o.depends({ mode: 'periodic_reboot' });

		o = s.taboption('general', widgets.DeviceSelect, 'interface', _('Interface（介面）'), _(
			'要監控/重啟的網路介面（Interface to monitor and/or restart）。'
		), _('<i>適用於 Ping Reboot / Restart Interface（Applies to Ping/Re-start interface modes）</i>'));
		o.depends({ mode: 'ping_reboot' });
		o.depends({ mode: 'restart_iface' });

		o = s.taboption('general', widgets.NetworkSelect, 'mmifacename', _('Name of ModemManager Interface（ModemManager 介面名稱）'), _(
			'若使用 ModemManager，可填入介面名稱讓 Watchcat 重啟該介面。（If using ModemManager, specify its name to restart it.）'
		));
		o.depends({ mode: 'restart_iface' });
		o.optional = true;

		o = s.taboption('general', form.Flag, 'unlockbands', _('Unlock Modem Bands（解鎖頻段）'), _(
			'若使用 ModemManager，重啟介面前先將 modem 設為允許使用任意頻段。（If using ModemManager, allow any band before restart.）'
		));
		o.default = '0';
		o.depends({ mode: 'restart_iface' });

		/* Service Recover options */
		o = s.taboption('general', form.Value, 'reboot_backoff', _('Reboot Backoff（重啟間隔）'), _(
			'兩次 reboot 的最小間隔（避免 reboot loop）。（Minimum time between two reboots; rate-limit to avoid reboot loops.）'
		));
		o.default = '1h';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Flag, 'disk_cleanup_enable', _('Disk Cleanup Enable（啟用磁碟清理）'), _(
			'僅在磁碟低於門檻時，保守清理 /root 下的「patch 產生備份」舊檔（不碰 Docker volumes）。清理紀錄見系統日誌或 /tmp/watchcat_disk_cleanup_last.txt。'
		));
		o.default = '1';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Value, 'disk_cleanup_keep', _('Disk Cleanup Keep（保留份數）'), _(
			'每一類備份保留最近 N 份，其餘刪除（Keep last N backups per category）。'
		));
		o.datatype = 'uinteger';
		o.default = '3';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Value, 'disk_path', _('Disk Path（磁碟路徑）'), _('要檢查剩餘空間的路徑（例如 / 或 /opt）。（Disk path to check free space for, e.g. / or /opt.）'));
		o.default = '/';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Value, 'disk_min_kb', _('Minimum Free Disk (KB)（最小剩餘 KB）'), _(
			'若剩餘空間低於此門檻，會視為 unhealthy 並記錄告警。（If below threshold, system is marked unhealthy and logs warning.）'
		));
		o.datatype = 'uinteger';
		o.default = '200000';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Flag, 'docker_check', _('Docker Health Check（Docker 健康檢查）'), _(
			'啟用後會檢查 `docker info`，不健康時嘗試重啟 dockerd。（When enabled, checks `docker info` and restarts dockerd if unhealthy.）'
		));
		o.default = '1';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Flag, 'chirpstack_check', _('ChirpStack Stack Check（ChirpStack 檢查）'), _(
			'啟用後會檢查 ChirpStack 容器並嘗試自動修復。（When enabled, checks ChirpStack containers and tries recovery.）'
		));
		o.default = '1';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Value, 'chirpstack_name_prefix', _('ChirpStack Container Prefix（容器前綴）'), _(
			'只有容器名稱以此開頭，才視為 ChirpStack stack 的一部分。（Only containers whose names start with this prefix are considered part of the stack.）'
		));
		o.default = 'chirpstack-docker_';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.DynamicList, 'chirpstack_required', _('ChirpStack Required Components（必要元件）'), _(
			'關鍵字（子字串匹配）：必須出現在 prefix 範圍內且正在 running 的容器名稱中。（Substring keywords that must appear in running container names under the prefix.）'
		));
		o.depends({ mode: 'service_recover' });
		o.optional = true;

		o = s.taboption('general', form.Value, 'chirpstack_compose_dir', _('ChirpStack Compose Directory（Compose 目錄）'), _(
			'包含 docker-compose.yml 的目錄，用於 stack recovery。（Directory containing docker-compose.yml used to recover the stack.）'
		));
		o.default = '/mnt/opensource-system/chirpstack-docker';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.ListValue, 'chirpstack_recover', _('ChirpStack Recover Strategy（修復策略）'), _(
			'當 ChirpStack stack 不健康時要採取的修復策略。（Recovery strategy when stack is unhealthy.）'
		));
		o.value('docker_restart_then_compose', _('Restart containers then Compose up（先重啟容器，再 Compose up）'));
		o.value('compose_up', _('Compose up only（只做 Compose up）'));
		o.default = 'docker_restart_then_compose';
		o.depends({ mode: 'service_recover' });

		o = s.taboption('general', form.Value, 'chirpstack_recover_cooldown', _('ChirpStack Recover Cooldown (seconds)（修復冷卻秒數）'), _(
			'兩次 ChirpStack 修復嘗試的最小間隔秒數。（Minimum seconds between two recover attempts.）'
		));
		o.datatype = 'uinteger';
		o.default = '300';
		o.depends({ mode: 'service_recover' });

		return m.render();
	}
});
LUCIFS
fi

/etc/init.d/rpcd restart 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
/etc/init.d/nginx restart 2>/dev/null || true

/etc/init.d/watchcat restart || /etc/init.d/watchcat start || true

ubus call service list '{"name":"watchcat"}' 2>/dev/null || true
ps w | grep -E "watchcat\.sh service_recover" | grep -v grep || true

echo "OK applied watchcat patch (service_recover)."
REMOTE

say "DONE"
