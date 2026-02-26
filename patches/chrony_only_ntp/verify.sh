#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage:
  ./verify.sh --ntp-server <ip_or_host> [--ntp-server <ip_or_host> ...]
EOF
}

SERVERS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ntp-server)
      [ $# -ge 2 ] || { echo "missing value for --ntp-server" >&2; usage; exit 2; }
      SERVERS="$SERVERS $2"
      shift 2
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

fail() { echo "VERIFY_FAIL: $*" >&2; exit 1; }

# 1) Services
if [ -x /etc/init.d/chronyd ]; then
  /etc/init.d/chronyd status >/dev/null 2>&1 || fail "chronyd not running"
else
  fail "/etc/init.d/chronyd missing"
fi

if [ -x /etc/init.d/sysntpd ]; then
  # sysntpd may exist but should be disabled/stopped
  /etc/init.d/sysntpd status >/dev/null 2>&1 && echo "WARN: sysntpd is running (expected stopped)" >&2 || true
fi

# 2) Config sanity
uci -q show chrony >/dev/null 2>&1 || fail "uci show chrony failed"

# Check that every expected server exists at least once in chrony pool list
for s in $SERVERS; do
  uci -q show chrony | grep -F "hostname='$s'" >/dev/null 2>&1 || fail "chrony missing server: $s"
done

# 3) Runtime sanity (best effort)
if command -v chronyc >/dev/null 2>&1; then
  chronyc tracking || true
  chronyc sources -v || true
fi

date

echo "VERIFY_OK"
