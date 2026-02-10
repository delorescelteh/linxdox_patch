# Chrony-only + Hide LuCI NTPC Page (Truth-only UI) Patch Bundle

Goal: **remove confusion** in LuCI by ensuring there is a single source of truth for time sync.

This bundle:
- Ensures **chronyd** is enabled & running (time sync service)
- Stops/disables **sysntpd** (ntpd wrapper) if present
- Stops/disables **ntpclient** service if present
- Hides the LuCI **“校時同步 / ntpc”** page by moving its menu entry:
  - `/usr/share/luci/menu.d/luci-app-ntpc.json`

**Important:** This bundle **does NOT set NTP server IPs**. Customer can configure time servers via the remaining (single) configuration path, without being misled by multiple UIs.

## Quick start (run on Mac/PC)
```sh
./deploy_chrony_only_patch.sh
```

## Verify
```sh
./verify_chrony_only_patch.sh root@<ip>
```

## What changes on device
- Moves file (if exists):
  - `/usr/share/luci/menu.d/luci-app-ntpc.json` → `/root/backup_chrony_only_patch_<ts>/luci-app-ntpc.json`
- Enables/restarts chronyd
- Disables sysntpd + ntpclient (if present)

## Rollback
Restore the moved menu file from the backup folder and restart `rpcd/uhttpd/nginx`.
