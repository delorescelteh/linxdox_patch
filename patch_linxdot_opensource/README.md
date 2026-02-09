# PATCH: patch_linxdot_opensource

## 5W (summary)
- **Why**: baseline Docker component may not fit our production needs (ChirpStack stack via Docker); need deterministic + recoverable ops.
- **What**: revise Docker config/storage/compose-like boot scheme + guardrails; provide apply/verify scripts.
- **Who**: Owner=Living, Operator=Delores.
- **When**: started 2026-02-10; applied TBD.
- **Where**: Linxdot/OpenWrt devices running Docker (baseline ref: 192.168.0.88). Repo folder `patch_linxdot_opensource/`.

Details:
- `docs/5W1H.md`

## Test scheme
- `docs/TEST_PLAN.md`

## How to start (phase 1)
1) Capture baseline:
```sh
./patch_linxdot_opensource/tools/capture_baseline_docker.sh root@<ip>
```
2) Decide design and implement apply/verify scripts.

## Evidence
- Baseline: `patch_linxdot_opensource/baseline/`
- After: `patch_linxdot_opensource/evidence/`
