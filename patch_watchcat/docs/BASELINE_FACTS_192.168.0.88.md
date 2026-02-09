# Watchcat baseline facts (192.168.0.88)

Source device: `192.168.0.88` (Linxdot 2.0.0.05-OPEN).
Baseline capture (local): `patch_watchcat/baseline/192.168.0.88_20260209_2119_fix/`

## UCI config (`/etc/config/watchcat`)
Observed:
- mode: `ping_reboot`
- pinghosts: `8.8.8.8`
- forcedelay: `30`
- period: `1h`

## Enablement (`/etc/rc.d`)
- `S97watchcat -> ../init.d/watchcat` (enabled)
- `K01watchcat -> ../init.d/watchcat`

## Init script (`/etc/init.d/watchcat`)
- procd service, `START=97`, `STOP=01`
- Supported modes: `periodic_reboot`, `ping_reboot`, `restart_iface`
- `ping_reboot` launches:
  - `/usr/bin/watchcat.sh ping_reboot <failure_period> <force_reboot_delay> <ping_hosts> <ping_period> <ping_size>`

## Script behavior (`/usr/bin/watchcat.sh`)
- Uses `/proc/uptime` (uptime-based).
- In `ping_reboot` mode: if continuous ping failures reach `failure_period`, it triggers `reboot_now`.
- `reboot_now` does:
  - `reboot &`
  - then after `forcedelay` triggers sysrq-b hard reboot (`/proc/sysrq-trigger`), which does not sync/unmount.

## Runtime snapshot (captured)
From `ps` on baseline:
- `/bin/sh /usr/bin/watchcat.sh ping_reboot 3600 30 8.8.8.8 60 standard`

## Implications / risks (from facts)
- `8.8.8.8` is a public Internet dependency; unsuitable for intranet-only sites.
- sysrq-b hard reboot increases risk of filesystem damage under certain failure modes.
