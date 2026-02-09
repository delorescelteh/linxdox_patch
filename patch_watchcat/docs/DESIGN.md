# patch_watchcat — Design (draft)

## Goal
Patch the **existing watchcat** (UCI + init.d + `/usr/bin/watchcat.sh`) so it can do layer-by-layer recovery for Linxdot (OpenWrt + Docker + ChirpStack), without adding a new watchdog daemon.

## Constraints / decisions
- Keep LuCI/UCI entry visible (do NOT hide watchcat).
- Avoid external ping dependency (e.g., 8.8.8.8) for intranet/no-Internet sites.
- Add a new mode implemented inside the **existing** `/usr/bin/watchcat.sh`.

## New mode
- Mode name: `service_recover`

### What it checks (phase 1)
1) Disk free space threshold (configurable)
2) Docker daemon availability (configurable)
3) ChirpStack stack containers running (prefix + required components match)

### Actions (phase 1)
Layered recovery (least disruptive first):
1) If disk free below threshold: log error; (no automatic cleanup in phase 1)
2) If ChirpStack stack unhealthy:
   - detection uses `chirpstack_name_prefix` + `chirpstack_required` (substring match against **running** container names)
   - try **container restart** first (restart any non-running containers under the prefix)
   - then reconcile using compose: `docker-compose up -d --remove-orphans` (or `docker compose up -d --remove-orphans`) in configured compose dir
   - rate-limit recovery by `chirpstack_recover_cooldown`
3) If docker not healthy: restart dockerd
4) If failure persists and exceeds `failure_period`, do a normal reboot, rate-limited by `reboot_backoff` (default 1h)

## UCI mapping (proposed)
`/etc/config/watchcat` new options in `config watchcat`:
- `option mode 'service_recover'`
- `option period '1h'`  (failure_period)
- `option reboot_backoff '1h'` (min time between reboots)
- `option disk_path '/'` (or `/opt` etc)
- `option disk_min_kb '200000'` (example)
- `option docker_check '1'`

## Acceptance criteria
- watchcat no longer reboots because of missing Internet.
- when docker is down, watchcat restarts dockerd.
- reboot happens only after `period` AND is rate-limited by `reboot_backoff`.
- all actions are logged via `logger -t watchcat[...]`.
