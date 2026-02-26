# luci_chrony_timesync_ui

Sync the "System → Time Synchronization" LuCI page and supporting cron status updater from device 248 to other devices.

What it installs:
- `/www/luci-static/resources/view/system/system.js` (Chrony UI enhancements)
- `/usr/sbin/chrony-status-update` (generates `/var/run/chrony-status/*.txt`)
- `/etc/crontabs/root` entry to run updater every minute

## Usage (on target device)

```sh
cd /root/linxdox_patch/patches/luci_chrony_timesync_ui
./apply.sh
./verify.sh

# if needed
./rollback.sh
```
