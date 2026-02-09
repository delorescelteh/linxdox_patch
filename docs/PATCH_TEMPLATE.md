# Patch Template (General Scheme)

> Purpose: standardize how we create, review, apply, and verify patches for Linxdot/OpenWrt devices.

## 0) Patch identity
- Patch name: `patch_<topic>`
- Patch ID: `YYYYMMDD_<short-topic>` (optional)
- Target device(s): model / firmware / IP range
- Author(s):
- Date started / date applied:

## 1) Why we patch (Problem statement)
- Symptom(s):
- Impact / risk:
- Root cause hypothesis:
- Evidence (logs, screenshots, UCI, repro steps):

## 2) What we patch (Scope)
- In-scope changes:
- Out-of-scope / non-goals:
- Risks / side effects:
- Rollback strategy:

## 3) Baseline capture (Before)
Checklist:
- [ ] Firmware banner + version string
- [ ] `/etc/config/*` relevant files captured
- [ ] `/etc/init.d/*` relevant scripts captured
- [ ] running processes (`ps w`) captured
- [ ] LuCI screenshots (if UI-related)

Store under:
- `patch_<topic>/baseline/`

## 4) Patch design
- Desired behavior (acceptance criteria):
- Decision points:
- Config mapping (UI ↔ UCI ↔ daemon):

## 5) Implementation
- Files changed on device:
- Files added:
- Script(s):
  - `patch_<topic>/tools/apply_*.sh`
  - `patch_<topic>/tools/verify_*.sh`
- Logging:

## 6) Test plan
### Functional tests
- Steps:
- Expected results:

### Failure / offline tests (if applicable)
- Steps:
- Expected results:

### Evidence to collect (After)
- [ ] key command outputs saved in `patch_<topic>/logs/`
- [ ] screenshots saved in `patch_<topic>/baseline/` or `patch_<topic>/evidence/`

## 7) Execution log (When / Who did)
- Timeline (timestamped):
- Operator:
- Commands executed:
- Devices affected:

## 8) Deliverables
- Patch folder: `patch_<topic>/`
- README for customer/operators
- One-line summary for boss

## 9) Appendix
- Links to issues/PRs
- Raw outputs
