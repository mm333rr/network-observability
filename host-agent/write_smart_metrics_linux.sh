#!/usr/bin/env bash
# =============================================================================
# write_smart_metrics_linux.sh — Linux SMART metrics writer for cron
# Writes SMART health to host-metrics/smart_metrics.prom every 5 min
# Uses same logic as scripts/smart_metrics.sh but writes to file (for cron)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${SCRIPT_DIR}/../host-metrics/smart_metrics.prom"
HOST="${HOST_HOSTNAME:-pi}"
TMPFILE="${OUTPUT}.tmp"

{
echo "# HELP smart_health SMART overall health (1=PASSED, 0=FAILED)"
echo "# TYPE smart_health gauge"
echo "# HELP smart_temperature_celsius Drive temperature in Celsius"
echo "# TYPE smart_temperature_celsius gauge"
echo "# HELP smart_reallocated_sectors Reallocated sector count"
echo "# TYPE smart_reallocated_sectors gauge"

for disk in $(lsblk -d -o NAME,TYPE --noheadings 2>/dev/null | awk '$2=="disk"{print "/dev/"$1}'); do
    disk_name=$(basename "$disk")
    health=$(smartctl -H "$disk" 2>/dev/null | grep "overall-health" | awk '{print $NF}')
    [[ -z "$health" ]] && continue
    [[ "$health" == "PASSED" ]] && hval=1 || hval=0
    echo "smart_health{disk=\"${disk_name}\",host=\"${HOST}\"} ${hval}"

    temp=$(smartctl -A "$disk" 2>/dev/null | grep -iE "^194|Temperature_Celsius" | head -1 | awk '{print $10}')
    [[ -z "$temp" ]] && temp=$(smartctl -A "$disk" 2>/dev/null | grep -i "Temperature:" | head -1 | awk '{print $2}')
    [[ -n "$temp" && "$temp" =~ ^[0-9]+$ ]] && \
        echo "smart_temperature_celsius{disk=\"${disk_name}\",host=\"${HOST}\"} ${temp}"

    reallocated=$(smartctl -A "$disk" 2>/dev/null | grep "Reallocated_Sector" | awk '{print $10}')
    [[ -n "$reallocated" ]] && \
        echo "smart_reallocated_sectors{disk=\"${disk_name}\",host=\"${HOST}\"} ${reallocated}"
done
} > "$TMPFILE" && mv "$TMPFILE" "$OUTPUT"
