# Docker Compose Patch — Checklist

## Baseline (before)
- [ ] Capture Docker configs
  - [ ] `/etc/config/dockerd`
  - [ ] `/etc/docker/daemon.json` (if exists)
  - [ ] `/etc/init.d/dockerd`
- [ ] Capture filesystem layout
  - [ ] `df -h`
  - [ ] `du -sh /opt/docker /var/lib/docker 2>/dev/null`
- [ ] Capture runtime
  - [ ] `ps w | egrep 'dockerd|containerd'`
  - [ ] `docker info`
  - [ ] `docker ps -a`
- [ ] Capture boot integration
  - [ ] `ls -l /etc/rc.d | grep -i dockerd`

## Design
- [ ] Decide compose mechanism (docker compose v2? compose file + systemd-like init? scripts?)
- [ ] Decide stack files location (e.g. `/opt/stack/`)
- [ ] Decide restart policy + order
- [ ] Decide logging strategy
- [ ] Disk guardrails (data_root, rotation, prune policy)

## Implementation
- [ ] apply script(s) under `patch_linxdot_opensource/tools/`
- [ ] verify script(s) under `patch_linxdot_opensource/tools/`
- [ ] rollback plan

## Verification (after)
- [ ] Reboot test
- [ ] docker OK + stack OK
- [ ] evidence saved
