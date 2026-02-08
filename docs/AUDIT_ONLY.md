# Audit-only

`audit_only.sh` scans a list of devices and generates a CSV report.

It is designed for offline customer environments and does not modify devices.

## Usage

```bash
./scripts/audit_only.sh --devices devices.txt --user root --site customerA
```

## Output
- `report_<site>_<timestamp>.csv`

Columns include:
- patch version markers (`/etc/linxdot_patch_version`, `/etc/linxdot_mode`)
- disk usage (`df /`)
- time stack detection (sysntpd/ntpd/chronyd/ntpclient)
- whether `luci-app-ntpc` is installed

