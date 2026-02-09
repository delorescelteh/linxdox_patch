# PATCH: patch_docker_compose

## Why we patch
- Baseline Docker component in Linxdot/OpenWrt may not match our desired production setup for a full ChirpStack stack.
- We want the Docker subsystem + compose workflow to be **deterministic**, **recoverable**, and **operator-friendly**.

## What we patch (scope)
- Baseline collection (before):
  - `/etc/config/dockerd`
  - Docker data root (`/opt/docker/` etc)
  - init scripts: `/etc/init.d/dockerd`
  - running processes: `dockerd`, `containerd`
  - (if present) any compose/stack files and where they live
- Revised Docker component scheme:
  - where compose files live
  - how containers are started on boot
  - logging policy
  - disk usage guardrails

## How to apply
TBD

## How to verify (tests)
- Docker daemon health:
  - `docker info` OK after reboot
- Stack health:
  - required containers running
  - ports reachable / health endpoints OK
- Persistence:
  - data survives reboot
  - logs are readable

## When / Who
- Started: 2026-02-10
- Operator: Delores (OpenClaw)

## Evidence
- Before: `patch_docker_compose/baseline/`
- After: `patch_docker_compose/evidence/`
