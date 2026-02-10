# NTP Runtime Warning Patch Bundle (Linxdot/OpenWrt)

This bundle installs an **NTP reachability health service** and patches LuCI login page to show a warning **only when the device cannot reach any NTP server**.

## What it does
- Installs `/usr/bin/ntp_health.sh`
- Installs `/etc/init.d/ntp-health` (procd loop; runs every 60s)
- Writes runtime status files in tmpfs:
  - `/tmp/ntp_health.txt`
  - `/tmp/ntp_health.unreliable` (present only when NTP is unreachable)
  - `/tmp/ntp_health.meta`
- Patches LuCI login page `/usr/lib/lua/luci/view/sysauth.htm`:
  - shows warning banner only when `/tmp/ntp_health.unreliable` exists
  - banner includes a Status line from `/tmp/ntp_health.txt`
- Removes the old always-on banner block if present (legacy marker)

## Requirements
- macOS/Linux with `ssh`
- Ability to SSH into device as root (default user: root)

## Quick start
```sh
./deploy_ntp_patch.sh
```
Enter:
- IP address (required)
- Username (default root)

`ssh` will prompt for password.

## Verify
```sh
./verify_ntp_patch.sh root@<ip>
```

## Notes
- This patch **does not change** NTP server configuration. It only improves observability & user warning behavior.
- If you also need to enforce chrony-only and set intranet NTP servers, that is a separate patch.
