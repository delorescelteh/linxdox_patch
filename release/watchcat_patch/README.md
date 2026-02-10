# Watchcat Patch Bundle (Linxdot/OpenWrt)

This bundle deploys a **watchcat service_recover** patch to a Linxdot/OpenWrt device.

## What it does
- Backs up existing files to `/root/backup_watchcat_patch_<timestamp>/`
- Updates `/etc/config/watchcat` with safe defaults and ChirpStack monitoring
- Rewrites `/etc/init.d/watchcat` to add `service_recover` mode (procd)
- Patches `/usr/bin/watchcat.sh` to implement `service_recover` logic
- **Conservative disk cleanup** when disk is below threshold (only removes older patch-generated backups under `/root/`, keeps last N)
- Patches LuCI UI (`/www/luci-static/resources/view/watchcat.js`) to support **Service Recover（服務恢復）** so UI matches runtime
- Restarts watchcat and reloads LuCI services

## ChirpStack monitoring logic
- Uses `chirpstack_name_prefix` (default: `chirpstack-docker_`) to scope containers.
- Uses `chirpstack_required` keywords (substring match) to ensure key components exist among **running** containers.
- On failure, recovery is layered:
  1) restart any **non-running** containers under the prefix
  2) run `docker-compose up -d --remove-orphans` (fallback `docker compose`)
  3) if docker daemon unhealthy: restart dockerd
  4) if failures persist beyond `period`: reboot (rate-limited by `reboot_backoff`)

## Requirements
- macOS (or Linux) with `ssh`
- network access to the device
- device account with root privileges (default user: `root`)

## Quick start
Run:
```sh
./deploy_watchcat_patch.sh
```
You will be prompted for:
- IP address (required)
- username (default: root)

`ssh` will prompt for password (default password is often `linxdot`).

## Verify
After deploy, you can run:
```sh
./verify_watchcat_patch.sh root@<ip>
```

## Notes
- This patch is designed for intranet/no-Internet deployments (no external ping dependency).
- To customize parameters, edit `deploy_watchcat_patch.sh` defaults or set env vars described in that file.
