# patch_linxdot_opensource — Test Plan

## Pre-checks (before apply)
- Record baseline evidence:
  - `/etc/config/dockerd`
  - `/etc/init.d/dockerd`
  - `ps w | egrep 'dockerd|containerd'`
  - `docker info` / `docker ps -a`
  - disk usage: `df -h`, `du -sh /opt/docker` (or actual data_root)

## Functional tests (after apply)
1) Docker daemon health
- `docker info` succeeds
- `docker ps` succeeds

2) Data root correctness
- Docker uses expected `data_root`
- No unexpected writes to rootfs

3) Boot persistence
- Reboot device
- Docker returns healthy
- Containers (if stack installed) come back automatically

4) Logging sanity
- Docker logs are not exploding storage
- log location and rotation strategy verified

## Negative / failure tests
- Stop docker and ensure recovery path works (if patch includes recovery)
- Simulate low disk (if safe) and ensure system does not brick; logs clearly show alert

## Evidence to collect
- Save command outputs into `patch_linxdot_opensource/evidence/<timestamp>/`
- Include “before vs after” diff of key configs.
