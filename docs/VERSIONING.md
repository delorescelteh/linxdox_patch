# Versioning

We use **SemVer** starting from **0.x.y**.

- `0.x.y` indicates rapid iteration; compatibility is best-effort.
- Patch kit artifacts should include the semver in file name.

## On-device version markers
Patches must write/update these files:

- `/etc/linxdot_patch_version`
  - Example: `0.1.0`
- `/etc/linxdot_patch_manifest.json`
  - JSON describing applied patch IDs, timestamps, operator, etc.

These files are the single source of truth when auditing fleets.

