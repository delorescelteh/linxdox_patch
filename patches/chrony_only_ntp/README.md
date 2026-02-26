# chrony_only_ntp patch

Goal: make the OpenWrt time stack **chrony-only** and set intranet NTP servers.

This patch is intended to be pulled to the target device (e.g. 192.168.0.9) and executed locally.

## Usage

On the device:

```sh
cd /root
git clone <YOUR_REPO_URL> linxdox_patch || true
cd linxdox_patch/patches/chrony_only_ntp

# Example: set 2 intranet NTP servers
./apply.sh --ntp-server 192.168.0.1 --ntp-server 192.168.0.2 --hide-ntpc-ui
./verify.sh --ntp-server 192.168.0.1 --ntp-server 192.168.0.2

# If needed
./rollback.sh
```

## Notes
- `apply.sh` stores backups under `/opt/linxdot-backups/patch_rollbacks/`.
- Under the hood it calls `../../tools/patch_time_stack.sh`.
