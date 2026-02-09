# LuCI baseline snapshots

- Device: Linxdot 2.0.0.05-OPEN A01 r17782-d6ec4dd717
- IP: 192.168.0.88
- Capture time (local): 2026-02-09 08:12+
- Notes:
  - Captured via browser automation.
  - HTTPS cert warning accepted (self-signed).
  - No configuration changes intentionally made; screenshots are read-only captures.

See `index.csv` for URL → filename mapping.

## Completion
- Completed captures for planned pages (system/services/docker/network/statistics).
- Skipped actions: no buttons clicked that would change config (save/apply/reboot/flash/scan/pull).

## Evidence: login-page NTP warning
- After applying `tools/patch_luci_login_notice.sh`, the LuCI login page shows a bilingual (zh-TW + English) warning banner about unreliable system time without reachable NTP.
- Screenshot: `070_login_ntp_warning.png`
