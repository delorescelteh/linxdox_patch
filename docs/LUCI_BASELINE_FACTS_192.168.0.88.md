# LuCI Baseline Facts (read-only)

Target baseline device:
- Model banner: **Linxdot 2.0.0.05-OPEN A01 r17782-d6ec4dd717**
- IP: **192.168.0.88**
- Capture folder: `baseline/luci_192.168.0.88_20260209_081246/`
- Total screenshots: **40** (see `index.csv` in the capture folder)

## 1) What we saw in LuCI (UI facts)

### Top-level navigation (left menu)
- Dashboard
- Status
- System
- Services
- Docker 虛擬平台 (DockerMan)
- Network
- Statistics
- Logout

### Status pages captured
- Overview, Routes, Firewall (iptables view), System Log, Processes
- Channel analysis
- Realtime graphs
- MultiWAN manager (status)

### System pages captured
- System (general system page)
- Administration (router password / SSH)
- ACL
- Software (opkg)
- Startup (init scripts)
- Scheduled tasks (crontab)
- Mount points
- **Time sync page: `/admin/system/ntpc` (LuCI app ntpc)**
- LEDs
- Flash/backup/firmware
- Custom commands
- Reboot page

### Services pages captured
- Watchcat
- ttyd
- mjpg-streamer

### Docker pages captured
- Config, Overview, Containers, Images, Networks, Volumes, Events

### Network pages captured
- Interfaces
- Wireless
- Routes
- DHCP & DNS
- Diagnostics
- Firewall
- MultiWAN manager

### Statistics pages captured
- Graphs
- Collectd config

## 2) UCI configuration facts (what config backs which UI)

UCI files read from `/etc/config` (baseline list includes: system, ntpclient, network, dhcp, firewall, mwan3, uhttpd, nginx, dockerd, luci, wireless, etc.)

### System time sync (sysntpd) — `/etc/config/system`
```
config timeserver 'ntp'
  option enabled '1'
  option enable_server '0'
  list server '0.openwrt.pool.ntp.org'
  list server '1.openwrt.pool.ntp.org'
  list server '2.openwrt.pool.ntp.org'
  list server '3.openwrt.pool.ntp.org'
```
Fact: the baseline image ships with **external** OpenWrt pool NTP servers.

### LuCI `校時同步` page (ntpc app) — `/etc/config/ntpclient`
This is a separate config namespace:
```
config ntpclient
  option interval 600
...
config ntpserver ... hostname ... port 123
```
Fact: the baseline has **two distinct NTP configuration stacks**: `system.ntp.server` and `ntpclient`.

### Network — `/etc/config/network`
- `lan` is static: **10.100.100.1/24** on `br-lan` (bridge over `wlan0`)
- `wan` is DHCP on `eth0`
- lan has `list dns '8.8.8.8'` and `option gateway '10.100.100.1'`
- `docker0` bridge device exists; `docker` interface proto none, auto 0

### DHCP/DNS — `/etc/config/dhcp`
- dnsmasq upstream servers include `8.8.8.8` and `168.95.1.1`
- `list notinterface 'wan'` present (dnsmasq not bound to wan)

### Firewall — `/etc/config/firewall`
- Defaults: input ACCEPT / output ACCEPT / forward REJECT
- zones: `lan` ACCEPT forward; `wan` masq; forwarding lan->wan
- `Allow-SSH-WAN` rule exists (TCP/22 allowed from `wan`)
- `docker` zone exists and forwards ACCEPT

### MultiWAN — `/etc/config/mwan3`
- Tracks public IPs (Google/OpenDNS) for wan availability
- Policies: balanced / wan_only / wanb_only etc.

### Web stack
- `/etc/config/uhttpd` listens on 80/443; `redirect_https '0'`.
- `/etc/config/nginx` includes `_redirect2ssl` that returns **302 https://$host$request_uri** on port 80.
  Fact: HTTP→HTTPS redirect behavior is controlled by **nginx**, not uhttpd.

### Docker
- `/etc/config/dockerd` sets `data_root '/opt/docker/'`, iptables enabled, blocks docker0 from wan.

### LuCI settings — `/etc/config/luci`
- theme: `/luci-static/openwrt2020`
- diagnostics defaults target `openwrt.org`

## 3) Operational conclusions (strictly from UI+UCI facts)
- Baseline firmware contains **multiple time management components** (sysntpd via `system.ntp.server`, ntpclient via `luci-app-ntpc` and `/etc/config/ntpclient`, plus other packages like chrony may exist).
- Offline customer environments will fail to sync with the default external NTP servers.
- Some UI pages are inherently dangerous (flash/reboot) even when only browsing; baseline capture avoided clicking action buttons.
