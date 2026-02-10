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
REACHABLE_COUNT=0

if command -v chronyc >/dev/null 2>&1; then
  # Determine reachability: if ALL sources have Reach=0, treat as unreachable.
  # chronyc sources format:
  # MS Name/IP Stratum Poll Reach LastRx ...
  SOURCES=$(chronyc -n sources 2>/dev/null || true)
  REACHABLE_COUNT=$(printf "%s\n" "$SOURCES" | awk 'NR>2 && NF>0 { if ($5 != "0") c++ } END { print c+0 }')

  TRACK=$(chronyc -n tracking 2>/dev/null || true)
  LEAP=$(printf "%s\n" "$TRACK" | awk -F': *' '/^Leap status/ {print $2; exit}')
  REFID=$(printf "%s\n" "$TRACK" | awk -F': *' '/^Reference ID/ {print $2; exit}')
  STRATUM=$(printf "%s\n" "$TRACK" | awk -F': *' '/^Stratum/ {print $2; exit}')

  if [ "$REACHABLE_COUNT" -le 0 ] 2>/dev/null; then
    RELIABLE=0
    REASON="ntp_unreachable"
    SUMMARY="NTP unreachable: cannot reach any NTP server (chrony sources reach=0)"
  else
    # Only show warning when unreachable; otherwise mark as reliable enough for banner suppression.
    RELIABLE=1
    REASON="ntp_reachable"
    SUMMARY="NTP reachable: sources_reachable=$REACHABLE_COUNT, leap_status=${LEAP:-?}, stratum=${STRATUM:-?}, refid=${REFID:-?}"
  fi
else
  RELIABLE=0
  REASON="chronyc_missing"
  SUMMARY="NTP unreachable: chronyc not installed"
fi

# Write outputs atomically
TMP=$(mktemp /tmp/ntp_health.XXXXXX)
{
  echo "time_iso=$NOW_ISO"
  echo "time_epoch=$NOW_EPOCH"
  echo "reliable=$RELIABLE"
  echo "reason=$REASON"
  echo "sources_reachable=$REACHABLE_COUNT"
} > "$TMP"
mv "$TMP" "$OUT_META"

echo "$SUMMARY" > "$OUT_TXT"

if [ "$RELIABLE" = "1" ]; then
  rm -f "$OUT_BAD"
else
  : > "$OUT_BAD"
fi
