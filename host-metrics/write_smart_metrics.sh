#!/usr/bin/env bash
# =============================================================================
# write_smart_metrics.sh — Writes SMART drive health metrics for Telegraf
# Run by LaunchAgent (com.capes.smart-metrics) every 5 minutes on the Mac host.
# Output: host-metrics/smart_metrics.prom, read by Telegraf inputs.file.
#
# Why host-side: diskutil and smartctl use macOS IOKit; not available in Docker.
# smartmontools must be installed: brew install smartmontools
# =============================================================================

OUTDIR="$(dirname "$0")"
TMPFILE="${OUTDIR}/smart_metrics.prom.tmp"
OUTFILE="${OUTDIR}/smart_metrics.prom"
HOST="macpro"

{
  echo "# HELP smart_health SMART overall health (1=PASSED, 0=FAILED)"
  echo "# TYPE smart_health gauge"
  echo "# HELP smart_temperature_celsius Drive temperature in Celsius"
  echo "# TYPE smart_temperature_celsius gauge"
  echo "# HELP smart_reallocated_sectors Reallocated sector count (early failure indicator)"
  echo "# TYPE smart_reallocated_sectors gauge"

  # Get all physical disks (not partitions)
  disks=$(diskutil list | grep "^/dev/disk" | grep -v "disk[0-9]*s[0-9]" | awk '{print $1}')

  for disk in $disks; do
    disk_name=$(basename "$disk")

    health=$(smartctl -H "$disk" 2>/dev/null | grep "overall-health" | awk '{print $NF}')
    if [ "$health" = "PASSED" ]; then
      echo "smart_health{disk=\"$disk_name\",host=\"$HOST\"} 1"
    elif [ -n "$health" ]; then
      echo "smart_health{disk=\"$disk_name\",host=\"$HOST\"} 0"
    fi

    temp=$(smartctl -A "$disk" 2>/dev/null | grep -i "temperature" | head -1 | awk '{print $10}')
    if [ -n "$temp" ] && echo "$temp" | grep -qE '^[0-9]+$'; then
      echo "smart_temperature_celsius{disk=\"$disk_name\",host=\"$HOST\"} $temp"
    fi

    reallocated=$(smartctl -A "$disk" 2>/dev/null | grep "Reallocated_Sector" | awk '{print $10}')
    if [ -n "$reallocated" ]; then
      echo "smart_reallocated_sectors{disk=\"$disk_name\",host=\"$HOST\"} $reallocated"
    fi
  done
} > "$TMPFILE"

mv "$TMPFILE" "$OUTFILE"
