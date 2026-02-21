#!/usr/bin/env bash
# =============================================================================
# smart_metrics.sh — Drive health via smartmontools
# Called by Telegraf [[inputs.exec]] every 5 minutes
# Outputs: Prometheus text — smart_health, smart_temperature_celsius,
#          smart_reallocated_sectors per disk
#
# Portable: detects macOS vs Linux and enumerates disks accordingly.
#   macOS: diskutil list (APFS, HFS+, external drives)
#   Linux: /dev/sd* + /dev/nvme* (typical Pi/server layout)
# =============================================================================

HOST="${HOST_HOSTNAME:-macpro}"

enumerate_disks() {
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS: get all physical disk nodes (exclude partitions like disk0s1)
        diskutil list | grep "^/dev/disk" | awk '{print $1}'
    else
        # Linux: physical block devices only (no partitions, no loop/ram)
        lsblk -d -o NAME,TYPE --noheadings 2>/dev/null \
            | awk '$2=="disk"{print "/dev/"$1}'
    fi
}

for disk in $(enumerate_disks); do
    disk_name=$(basename "$disk")

    # SMART overall health
    health=$(smartctl -H "$disk" 2>/dev/null | grep "overall-health" | awk '{print $NF}')
    if [[ "$health" == "PASSED" ]]; then
        health_val=1
    elif [[ -n "$health" ]]; then
        health_val=0
    else
        continue  # not a SMART disk (virtual, optical, etc.)
    fi
    echo "smart_health{disk=\"${disk_name}\",host=\"${HOST}\"} ${health_val}"

    # Temperature — attribute 194 is standard; NVMe uses a different path
    temp=$(smartctl -A "$disk" 2>/dev/null \
        | grep -iE "^194|Temperature_Celsius" \
        | head -1 | awk '{print $10}')
    # NVMe fallback
    if [[ -z "$temp" ]]; then
        temp=$(smartctl -A "$disk" 2>/dev/null \
            | grep -i "Temperature:" | head -1 | awk '{print $2}')
    fi
    if [[ -n "$temp" ]] && [[ "$temp" =~ ^[0-9]+$ ]]; then
        echo "smart_temperature_celsius{disk=\"${disk_name}\",host=\"${HOST}\"} ${temp}"
    fi

    # Reallocated sectors (HDDs only -- NVMe won't have this)
    reallocated=$(smartctl -A "$disk" 2>/dev/null \
        | grep "Reallocated_Sector" | awk '{print $10}')
    if [[ -n "$reallocated" ]]; then
        echo "smart_reallocated_sectors{disk=\"${disk_name}\",host=\"${HOST}\"} ${reallocated}"
    fi
done
