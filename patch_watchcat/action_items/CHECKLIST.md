# Watchcat Patch — Checklist

## Baseline (before)
- [ ] Capture configs
  - [ ] `/etc/config/watchcat`
- [ ] Capture init + scripts
  - [ ] `/etc/init.d/watchcat`
  - [ ] `/usr/bin/watchcat.sh` (or referenced script)
- [ ] Capture runtime
  - [ ] `ps w | grep watchcat`
  - [ ] `logread | grep -i watchcat` (if any)
  - [ ] `ls -1 /etc/rc.d | grep watchcat` (enable state)

## Design
- [ ] Decide health check target(s)
- [ ] Decide failure criteria (count/interval/timeout)
- [ ] Decide actions order
  - [ ] restart network/service
  - [ ] reboot only as last resort
- [ ] Backoff/rate-limit to avoid reboot storms
- [ ] Logging strategy + retention safety

## Implementation
- [ ] `patch_watchcat/tools/apply_watchcat.sh`
- [ ] `patch_watchcat/tools/verify_watchcat.sh`
- [ ] rollback plan documented

## Verification (after)
- [ ] Confirm behavior under simulated failure
- [ ] Collect evidence logs/screens
