#!/bin/sh
# Create a standard patch folder skeleton.
# Usage:
#   tools/new_patch.sh <topic>
# Example:
#   tools/new_patch.sh time_stack

set -eu
TOPIC=${1:-}
[ -n "$TOPIC" ] || { echo "usage: $0 <topic>" >&2; exit 2; }

DIR="patch_${TOPIC}"
[ -e "$DIR" ] && { echo "exists: $DIR" >&2; exit 1; }

# NOTE: avoid brace-expansion for portability (/bin/sh may not support it)
mkdir -p "$DIR/docs" "$DIR/tools" "$DIR/notes" "$DIR/action_items" \
  "$DIR/memory" "$DIR/baseline" "$DIR/evidence" "$DIR/logs"

cat > "$DIR/README.md" <<'MD'
# PATCH: patch_<topic>

## Why we patch
- 

## What we patch
- 

## How to apply
- 

## How to verify (tests)
- 

## When / Who
- Started:
- Applied:
- Operator:

## Evidence
- Before:
- After:
MD

cat > "$DIR/action_items/CHECKLIST.md" <<'MD'
# Checklist

## Baseline (before)
- [ ] firmware banner/version
- [ ] relevant `/etc/config/*`
- [ ] relevant `/etc/init.d/*`
- [ ] `ps w` snapshot
- [ ] LuCI screenshots (if needed)

## Patch
- [ ] apply script prepared
- [ ] rollback plan prepared

## Verify (after)
- [ ] verify script run
- [ ] evidence collected (logs/screens)
MD

echo "OK: created $DIR"
