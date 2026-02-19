#!/usr/bin/env bash
# =============================================================================
# smart_metrics.sh — Polls drive health via smartmontools
# Called by Telegraf [[inputs.exec]] every 5 minutes
# Outputs: SMART health status and temperature per disk
# =============================================================================

HOST="macpro"

# Get all physical disks
disks=$(diskutil list | grep "^/dev/disk" | grep -v "disk[0-9]s" | awk '{print $1}')

for disk in $disks; do
    disk_name=$(basename "$disk")

    # Health status (PASSED=1, FAILED=0)
    health=$(smartctl -H "$disk" 2>/dev/null | grep "overall-health" | awk '{print $NF}')
    if [ "$health" = "PASSED" ]; then
        health_val=1
    elif [ -n "$health" ]; then
        health_val=0
    else
        continue  # not a SMART disk (e.g. fusion, virtual)
    fi
    echo "smart_health{disk=\"$disk_name\",host=\"$HOST\"} $health_val"

    # Temperature
    temp=$(smartctl -A "$disk" 2>/dev/null | grep -i "temperature" | head -1 | awk '{print $10}')
    if [ -n "$temp" ] && [ "$temp" -eq "$temp" ] 2>/dev/null; then
        echo "smart_temperature_celsius{disk=\"$disk_name\",host=\"$HOST\"} $temp"
    fi

    # Reallocated sectors (early failure indicator)
    reallocated=$(smartctl -A "$disk" 2>/dev/null | grep "Reallocated_Sector" | awk '{print $10}')
    if [ -n "$reallocated" ]; then
        echo "smart_reallocated_sectors{disk=\"$disk_name\",host=\"$HOST\"} $reallocated"
    fi
done
