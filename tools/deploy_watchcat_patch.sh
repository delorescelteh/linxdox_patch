#!/bin/sh
set -eu

# deploy_watchcat_patch.sh
# One-command deploy for patch_watchcat to a Linxdot/OpenWrt device.
# Runs apply + verify via SSH from macOS.
#
# Usage:
#   ./tools/deploy_watchcat_patch.sh root@<ip>
#   SSH_OPTS='-J root@<jump_ip>' ./tools/deploy_watchcat_patch.sh root@<ip>
#   BRANCH=watchcat-service-recover ./tools/deploy_watchcat_patch.sh root@<ip>
#
# Notes:
# - This script is meant to be run inside the linxdox_patch repo.
# - It will switch git branch (no stash). Commit/stash first if needed.

TARGET=${1:-}
[ -n "$TARGET" ] || { echo "usage: $0 root@<ip>" >&2; exit 2; }

BRANCH=${BRANCH:-watchcat-service-recover}
SSH_OPTS=${SSH_OPTS:-}

say() { echo "[deploy_watchcat_patch] $*"; }

die() { echo "[deploy_watchcat_patch] ERROR: $*" >&2; exit 1; }

# Ensure we're in repo root
[ -d .git ] || die "run this from repo root (expected .git/)"

say "target=$TARGET"
say "branch=$BRANCH"
[ -n "$SSH_OPTS" ] && say "SSH_OPTS=$SSH_OPTS"

# Basic clean check (we don't auto-stash to avoid surprises)
if ! git diff --quiet || ! git diff --cached --quiet; then
  die "git working tree not clean. Please commit/stash before deploy."
fi

say "checking out $BRANCH"
git checkout "$BRANCH" >/dev/null

say "pulling latest"
git pull --ff-only >/dev/null || say "WARN: git pull failed (offline?) continuing"

APPLY=./patch_watchcat/tools/apply_watchcat.sh
VERIFY=./patch_watchcat/tools/verify_watchcat.sh

[ -x "$APPLY" ] || die "missing or not executable: $APPLY"
[ -x "$VERIFY" ] || die "missing or not executable: $VERIFY"

# apply/verify honor SSH_CMD/SSH_OPTS (for ProxyJump, custom identity, port, etc)
export SSH_OPTS
export SSH_CMD

say "apply"
"$APPLY" "$TARGET"

say "verify"
"$VERIFY" "$TARGET"

say "DONE"
