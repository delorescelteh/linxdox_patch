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
Because container list is pending (we will decide after ChirpStack install), phase 1 implements:
1) Disk free space threshold (configurable)
2) Docker daemon availability (configurable)

### Actions (phase 1)
- If disk free below threshold: log error; (no automatic cleanup in phase 1)
- If docker not healthy: restart dockerd
- If recovery repeatedly fails and exceeds `failure_period`, do a normal reboot, rate-limited:
  - backoff: 1 hour (configurable)

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
