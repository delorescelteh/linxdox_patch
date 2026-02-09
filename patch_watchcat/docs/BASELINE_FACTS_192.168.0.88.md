# Watchcat baseline facts (192.168.0.88)

Source device: `192.168.0.88` (Linxdot 2.0.0.05-OPEN).
Evidence folder: `patch_watchcat/baseline/192.168.0.88_20260209_212307_txt/`

## UCI config (`/etc/config/watchcat`)
Observed:
- `mode = ping_reboot`
- `pinghosts = 8.8.8.8`
- `forcedelay = 30`
- `period = 1h`

## Enablement (`/etc/rc.d`)
- `S97watchcat -> ../init.d/watchcat` (enabled)
- `K01watchcat -> ../init.d/watchcat`

## Runtime process
Observed command line:
- `/bin/sh /usr/bin/watchcat.sh ping_reboot 3600 30 8.8.8.8 60 standard`

Interpretation:
- failure_period = 3600s (1h)
- force_reboot_delay = 30s
- ping host = 8.8.8.8
- ping interval = 60s
- ping size = standard

## Script behavior (`/usr/bin/watchcat.sh`)
- Uses `/proc/uptime` (uptime-based).
- In `ping_reboot` mode: if continuous ping failures reach `failure_period`, triggers `reboot_now`.
- `reboot_now` calls `reboot &`, then after `force_reboot_delay` triggers sysrq-b hard reboot:
  - `echo 1 > /proc/sys/kernel/sysrq`
  - `echo b > /proc/sysrq-trigger`
  (immediate reboot without syncing/unmounting filesystems)

## Notes / risks implied by baseline facts
- Single public target `8.8.8.8` is unsuitable for intranet/no-Internet deployments.
- sysrq-b hard reboot increases risk of filesystem corruption under some failure modes.
