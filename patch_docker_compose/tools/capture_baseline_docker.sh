#!/bin/sh
# Capture Docker baseline facts from a target device.
# Usage: ./capture_baseline_docker.sh root@<ip>

set -eu
TARGET=${1:-}
[ -n "$TARGET" ] || { echo "usage: $0 root@<ip>" >&2; exit 2; }

TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="patch_docker_compose/baseline/${TARGET#*@}_$TS"
mkdir -p "$OUTDIR"

run() {
  name="$1"; shift
  printf "# %s\n" "$*" > "$OUTDIR/$name.txt"
  ssh "$TARGET" "$@" >> "$OUTDIR/$name.txt" 2>&1 || true
}

run etc_config_dockerd "cat /etc/config/dockerd"
run etc_init_dockerd "sed -n '1,260p' /etc/init.d/dockerd"
run ps_docker "ps w | egrep 'dockerd|containerd' | grep -v grep"
run rc_dockerd "ls -l /etc/rc.d | grep -i dockerd || true"
run df_h "df -h"
run du_docker_roots "du -sh /opt/docker /var/lib/docker 2>/dev/null || true"
run docker_info "docker info"
run docker_ps "docker ps -a"

cat > "$OUTDIR/README.md" <<MD
# Docker baseline capture

- Target: $TARGET
- Time: $TS
- Files: *.txt are command outputs.
MD

echo "OK: captured to $OUTDIR"
