# PATCH: patch_watchcat

## Why we patch
- Watchcat controls automated recovery actions (e.g. ping watchdog → reboot).
- In the field there is risk of **reboot loops / excessive recovery** when root cause is not connectivity (disk full, wrong time, no Internet).
- Goal: make watchcat behavior **predictable**, **rate-limited**, and **auditable**.

## What we patch (scope)
- Baseline collection of existing watchcat config + scripts.
- Define new watchcat scheme:
  - health check target(s)
  - failure criteria (debounce/threshold)
  - action sequence (restart service/network before reboot)
  - backoff/rate-limit
  - logging strategy
- Provide apply + verify scripts.

## How to apply
TBD (to be filled after baseline collection + design decision).

## How to verify (tests)
- Confirm config + runtime matches intended scheme.
- Simulate failure and confirm:
  - triggers only after threshold
  - backoff works
  - logs are written

## When / Who
- Started: 2026-02-09
- Operator: Delores (OpenClaw)

## Evidence
- Before: `patch_watchcat/baseline/`
- After: `patch_watchcat/evidence/`
