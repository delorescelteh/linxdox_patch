# init.d Baseline Facts (read-only)

Target baseline device:
- Firmware: **Linxdot 2.0.0.05-OPEN A01 r17782-d6ec4dd717**
- IP: **192.168.0.88**
- Data source: `/etc/init.d/*`, `/etc/rc.d/*` and `ps` (read-only)

## 1) init scripts present
`/etc/init.d` includes (selected highlights):
- Time: `chronyd`, `sysntpd`, `sysfixtime`
- Network: `network`, `firewall`, `dnsmasq`, `mwan3`, `odhcpd`, `qos`, `wireless`, `dropbear`, `sshd`
- Web/UI: `nginx`, `uhttpd`, `uwsgi`, `rpcd`, `ttyd`, `luci_statistics`
- Docker: `dockerd`, (and `mdadm`, `fstab` etc.)
- Device/vendor: `linxdot_setup`, `linxdot_wifi`, `linxdot_check`, `adb-enablemodem`, `check_first_fast_sync`

Notably **missing** (as init scripts):
- `/etc/init.d/ntpd` (no standalone init script)
- `/etc/init.d/ntpclient` (even though `/etc/config/ntpclient` exists)

## 2) enabled services (boot order facts)
The enablement is represented by symlinks under `/etc/rc.d/`.

### Key enabled S* entries (subset)
- `S15chronyd`
- `S19dnsmasq`, `S19firewall`, `S19mwan3`
- `S20network`
- `S50cron`, `S50sshd`
- `S79uwsgi`, `S80nginx`, `S80collectd`
- `S97linxdot_wifi`, `S97watchcat`
- `S98sysntpd`
- `S99dockerd`, `S99ttyd`, `S99linxdot_check`, `S99linxdot_setup`

### Observation
Baseline image enables **both** `chronyd` and `sysntpd` at boot (potentially overlapping time-management stacks).

## 3) Time stack: what actually runs
From `ps` on the baseline:
- `chronyd` is running: `/usr/sbin/chronyd -n`
- `ntpd` is running inside a procd/ujail instance:
  - `{ntpd} /sbin/ujail ...`
  - `/usr/sbin/ntpd -n -N -S /usr/sbin/ntpd-hotplug -p 0.openwrt.pool.ntp.org ...`

### What this implies
- The `sysntpd` init script uses `PROG=/usr/sbin/ntpd` and spawns the `ntpd` process.
- Therefore, **"sysntpd" ≈ the service wrapper**, while **"ntpd" is the binary actually doing NTP**.
- `chronyd` is a second, separate time daemon enabled and running.

## 4) Web/UI stack: what runs
From `ps`:
- `nginx` master + multiple workers
- `ttyd` on `br-lan`

Combined with UCI (see `docs/LUCI_BASELINE_FACTS_192.168.0.88.md`):
- nginx provides HTTP→HTTPS redirect (`_redirect2ssl` server on port 80)
- uhttpd is configured to listen on 80/443 and provides the LuCI Lua entrypoint

## 5) Fleet-relevant baseline risks (facts)
- **Overlapping time daemons** (`chronyd` + `sysntpd/ntpd`) increase the chance of inconsistent time behavior.
- `/etc/config/ntpclient` exists and LuCI exposes `/admin/system/ntpc`, but there is no `/etc/init.d/ntpclient` script present → UI may configure a stack that is not actually managed as a service.

## Appendix: references
- init scripts: `/etc/init.d/chronyd`, `/etc/init.d/sysntpd`
- enablement: `/etc/rc.d/S*`
- process snapshot: `ps w | egrep 'chronyd|ntpd|...'
