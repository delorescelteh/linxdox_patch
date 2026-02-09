# NTP / Time Reliability — Action Items Checklist

Owner: Living

## Goal
Make system time reliability **observable** and LuCI behavior **non-confusing**:
- **Single time daemon**: chrony-only
- **UI**: remove duplicate NTP-setting entry (hide luci-app-ntpc)
- **Reliability**: show warning only when *actually* not synced (chronyc-based)

## On-device patch items (target device)
### A) Enforce chrony-only
- [ ] Run `tools/patch_time_stack.sh --ntp-server <INTRANET_NTP_1> [--ntp-server <INTRANET_NTP_2> ...] --hide-ntpc-ui`
- [ ] Verify only chrony is running:
  - [ ] `ps w | egrep 'chronyd|ntpd'`
  - [ ] Expect: `chronyd` present, `ntpd` absent
- [ ] Verify boot enablement:
  - [ ] `ls -1 /etc/rc.d | grep -E 'chronyd|sysntpd'`
  - [ ] Expect: `S15chronyd` present, `S98sysntpd` absent

### B) Install runtime NTP reliability monitor (chrony tracking)
- [ ] Install `ntp-health` service + conditional LuCI login warning (based on chronyc tracking)
- [ ] Verify status files:
  - [ ] `cat /tmp/ntp_health.txt`
  - [ ] `test -f /tmp/ntp_health.unreliable && echo UNRELIABLE || echo RELIABLE`

### C) Evidence screenshots (for record)
- [ ] Login page when **RELIABLE**: banner should **NOT** show
- [ ] Login page when **UNRELIABLE**: banner **shows** + includes `Status:` line

## Customer environment items
- [ ] Collect customer intranet NTP server(s): IP/FQDN, reachable from device
- [ ] Confirm no external Internet assumption
- [ ] Ensure any cleanup/retention scripts are time-independent (keep-last-N / disk-threshold)

## Notes
- UI time display being correct does **not** prove NTP is syncing. Use `chronyc tracking`/daemon output.
