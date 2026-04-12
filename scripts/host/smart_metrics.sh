#!/usr/bin/env bash
# =============================================================================
# smart_metrics_host.sh — Drive SMART health via smartmontools on the HOST.
# Called by capes-smart-metrics.timer every 5 minutes.
# Writes Prometheus text to /run/telegraf-smart/smart.prom — telegraf reads
# this via [[inputs.file]] with data_format="prometheus".
#
# Metrics:
#   smart_health{disk,host}                  1=PASSED 0=FAILED
#   smart_temperature_celsius{disk,host}     drive temp in °C
#   smart_reallocated_sectors{disk,host}     reallocated sector count (HDDs)
#
# Requires: smartmontools, root (or CAP_SYS_RAWIO / disk group)
# =============================================================================
set -uo pipefail

HOST="mbuntu"
OUT_DIR="/run/telegraf-smart"
TMP="${OUT_DIR}/smart.prom.tmp"
OUT="${OUT_DIR}/smart.prom"

mkdir -p "${OUT_DIR}"
: > "${TMP}"

enumerate_disks() {
    lsblk -d -o NAME,TYPE --noheadings 2>/dev/null \
        | awk '$2=="disk"{print "/dev/"$1}'
}

for disk in $(enumerate_disks); do
    disk_name=$(basename "$disk")

    health=$(smartctl -H "$disk" 2>/dev/null | grep "overall-health" | awk '{print $NF}')
    if [[ "$health" == "PASSED" ]]; then
        health_val=1
    elif [[ -n "$health" ]]; then
        health_val=0
    else
        continue
    fi
    echo "smart_health{disk=\"${disk_name}\",host=\"${HOST}\"} ${health_val}" >> "${TMP}"

    # Temperature — SATA attr 194; NVMe fallback
    temp=$(smartctl -A "$disk" 2>/dev/null \
        | grep -iE "^194|Temperature_Celsius" | head -1 | awk '{print $10}')
    if [[ -z "$temp" ]]; then
        temp=$(smartctl -A "$disk" 2>/dev/null \
            | grep -i "Temperature:" | head -1 | awk '{print $2}')
    fi
    if [[ -n "$temp" && "$temp" =~ ^[0-9]+$ ]]; then
        echo "smart_temperature_celsius{disk=\"${disk_name}\",host=\"${HOST}\"} ${temp}" >> "${TMP}"
    fi

    # Reallocated sectors (HDDs only)
    reallocated=$(smartctl -A "$disk" 2>/dev/null \
        | grep "Reallocated_Sector" | awk '{print $10}')
    if [[ -n "$reallocated" ]]; then
        echo "smart_reallocated_sectors{disk=\"${disk_name}\",host=\"${HOST}\"} ${reallocated}" >> "${TMP}"
    fi
done

mv "${TMP}" "${OUT}"
