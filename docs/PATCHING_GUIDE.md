# Patching Guide

## Patch types
- config patch (UCI edits)
- service patch (init.d/procd)
- LuCI UI patch
- cleanup/guard patch (disk/time independent)

## Patch requirements (must follow)
- Create an Issue file under `issues/` (see template)
- Create patch spec under `patches/`
- Add to `CHANGELOG.md`
- Bump patch kit version using **SemVer 0.x.y** (see `docs/VERSIONING.md`)
- **On-device markers are mandatory** for any patch that changes device behavior:
  - `/etc/linxdot_patch_version` must be updated
  - `/etc/linxdot_patch_manifest.json` must record applied patch IDs + timestamp + operator

## Fleet management (offline reality)
- Do not assume customers can self-update.
- Always provide an **audit-only** mode first (no changes), producing a report which can be returned.
- Use the audit report to plan baselines and staggered rollout.

