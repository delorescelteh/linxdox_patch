#!/bin/sh
# Write NTP reliability status based on chrony sync state.
# Output files (tmpfs):
# - /tmp/ntp_health.txt         human-readable single-line summary
# - /tmp/ntp_health.unreliable  present when NOT reliable
# - /tmp/ntp_health.meta        key=value lines for debugging

set -eu

OUT_TXT=/tmp/ntp_health.txt
OUT_BAD=/tmp/ntp_health.unreliable
OUT_META=/tmp/ntp_health.meta

NOW_EPOCH=$(date +%s)
NOW_ISO=$(date -Iseconds 2>/dev/null || date)

# Default
RELIABLE=0
REASON="unknown"
SUMMARY="NTP status unknown"

if command -v chronyc >/dev/null 2>&1; then
  # chronyc may fail if daemon not ready
  TRACK=$(chronyc -n tracking 2>/dev/null || true)

  # Determine sync via Leap status (preferred)
  LEAP=$(printf "%s\n" "$TRACK" | awk -F': *' '/^Leap status/ {print $2; exit}')
  REFID=$(printf "%s\n" "$TRACK" | awk -F': *' '/^Reference ID/ {print $2; exit}')
  STRATUM=$(printf "%s\n" "$TRACK" | awk -F': *' '/^Stratum/ {print $2; exit}')
  REFTIME=$(printf "%s\n" "$TRACK" | awk -F': *' '/^Ref time/ {print $2; exit}')
  LASTOFF=$(printf "%s\n" "$TRACK" | awk -F': *' '/^Last offset/ {print $2; exit}')

  if [ -n "${LEAP:-}" ]; then
    case "$LEAP" in
      Normal)
        RELIABLE=1
        REASON="chrony_synced"
        SUMMARY="NTP synced (chrony): stratum=${STRATUM:-?}, refid=${REFID:-?}, ref_time=${REFTIME:-?}, last_offset=${LASTOFF:-?}"
        ;;
      *Not*sync*|*not*sync*)
        RELIABLE=0
        REASON="chrony_not_synchronised"
        SUMMARY="NTP NOT synced (chrony): leap_status=$LEAP"
        ;;
      *)
        # Other leap statuses exist; treat non-Normal as not reliable
        RELIABLE=0
        REASON="chrony_leap_$LEAP"
        SUMMARY="NTP NOT reliable (chrony): leap_status=$LEAP"
        ;;
    esac
  else
    RELIABLE=0
    REASON="chrony_no_tracking"
    SUMMARY="NTP NOT reliable: chronyc tracking unavailable"
  fi
else
  RELIABLE=0
  REASON="chronyc_missing"
  SUMMARY="NTP NOT reliable: chronyc not installed"
fi

# Write outputs atomically
TMP=$(mktemp /tmp/ntp_health.XXXXXX)
{
  echo "time_iso=$NOW_ISO"
  echo "time_epoch=$NOW_EPOCH"
  echo "reliable=$RELIABLE"
  echo "reason=$REASON"
} > "$TMP"
mv "$TMP" "$OUT_META"

echo "$SUMMARY" > "$OUT_TXT"

if [ "$RELIABLE" = "1" ]; then
  rm -f "$OUT_BAD"
else
  : > "$OUT_BAD"
fi
