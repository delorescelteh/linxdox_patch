#!/bin/sh
set -eu

# Apply patch: chrony-only time stack + intranet NTP servers
# Wrapper for: ../../tools/patch_time_stack.sh

usage() {
  cat <<'EOF'
Usage:
  ./apply.sh --ntp-server <ip_or_host> [--ntp-server <ip_or_host> ...] [--hide-ntpc-ui]

Examples:
  ./apply.sh --ntp-server 192.168.0.1 --ntp-server 192.168.0.2 --hide-ntpc-ui
EOF
}

BKBASE="${ROLLBACK_BASE:-/opt/linxdot-backups/patch_rollbacks}"
TS="$(date +%Y%m%d_%H%M%S)"
BKDIR="$BKBASE/chrony_only_ntp_$TS"

mkdir -p "$BKDIR"

# Parse args
SERVERS=""
HIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ntp-server)
      [ $# -ge 2 ] || { echo "missing value for --ntp-server" >&2; usage; exit 2; }
      SERVERS="$SERVERS --ntp-server $2"
      shift 2
      ;;
    --hide-ntpc-ui)
      HIDE="--hide-ntpc-ui"
      shift 1
      ;;
    -h|--help)
      usage; exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      usage
      exit 2
      ;;
  esac
done

[ -n "$SERVERS" ] || { echo "need at least one --ntp-server" >&2; usage; exit 2; }

# Backups (best effort)
cp -a /etc/config/chrony "$BKDIR/" 2>/dev/null || true
cp -a /etc/config/system "$BKDIR/" 2>/dev/null || true
cp -a /etc/config/ntpclient "$BKDIR/" 2>/dev/null || true
cp -a /usr/share/luci/menu.d/luci-app-ntpc.json "$BKDIR/" 2>/dev/null || true

# Record rollback pointer
echo "$BKDIR" > ./LAST_BACKUP_DIR

# Apply patch
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
TOOL="$SCRIPT_DIR/../../tools/patch_time_stack.sh"

[ -x "$TOOL" ] || { echo "missing tool: $TOOL" >&2; exit 1; }

sh "$TOOL" $SERVERS $HIDE

echo "OK: applied chrony_only_ntp"
echo "Backup: $BKDIR"
