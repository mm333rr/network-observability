#!/usr/bin/env bash
# =============================================================================
# nas_metrics_host.sh — Runs on mbuntu HOST (not inside telegraf container).
# Called by capes-nas-metrics.timer every 5 minutes.
# Writes Prometheus text to /run/telegraf-nas/nas.prom — telegraf reads this
# via [[inputs.file]] with data_format="prometheus".
#
# Metrics:
#   nas_up                              always 1 when script runs
#   nas_zpool_health{pool}              1=ONLINE 0=degraded/faulted
#   nas_zpool_capacity_pct{pool}        integer % used
#   nas_zpool_read_errors{pool,vdev}    per-vdev read errors
#   nas_zpool_write_errors{pool,vdev}   per-vdev write errors
#   nas_zpool_cksum_errors{pool,vdev}   per-vdev checksum errors
#   nas_memory_usage_pct                RAM used %
#   nas_disk_root_usage_pct             / filesystem used %
# =============================================================================
set -euo pipefail

HOST="mbuntu"
POOL="tank"
OUT_DIR="/run/telegraf-nas"
TMP="${OUT_DIR}/nas.prom.tmp"
OUT="${OUT_DIR}/nas.prom"

mkdir -p "${OUT_DIR}"
: > "${TMP}"

# --- nas_up ------------------------------------------------------------------
echo "nas_up{host=\"${HOST}\"} 1" >> "${TMP}"

# --- ZFS pool health and capacity --------------------------------------------
while IFS=$'\t' read -r name size alloc free cap health rest; do
    cap_num="${cap//%/}"
    [[ "$health" == "ONLINE" ]] && health_val=1 || health_val=0
    echo "nas_zpool_health{pool=\"${name}\",host=\"${HOST}\"} ${health_val}" >> "${TMP}"
    echo "nas_zpool_capacity_pct{pool=\"${name}\",host=\"${HOST}\"} ${cap_num}" >> "${TMP}"
done < <(zpool list -H -o name,size,alloc,free,cap,health 2>/dev/null)

# --- Per-vdev error counts ---------------------------------------------------
while IFS= read -r line; do
    if [[ "$line" =~ ^[[:space:]]+(sd[a-z]+|nvme[0-9]+n[0-9]+)[[:space:]]+([A-Z]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+)[[:space:]]+([0-9]+) ]]; then
        vdev="${BASH_REMATCH[1]}"
        read_e="${BASH_REMATCH[3]}"
        write_e="${BASH_REMATCH[4]}"
        cksum_e="${BASH_REMATCH[5]}"
        echo "nas_zpool_read_errors{pool=\"${POOL}\",vdev=\"${vdev}\",host=\"${HOST}\"} ${read_e}" >> "${TMP}"
        echo "nas_zpool_write_errors{pool=\"${POOL}\",vdev=\"${vdev}\",host=\"${HOST}\"} ${write_e}" >> "${TMP}"
        echo "nas_zpool_cksum_errors{pool=\"${POOL}\",vdev=\"${vdev}\",host=\"${HOST}\"} ${cksum_e}" >> "${TMP}"
    fi
done < <(zpool status "${POOL}" 2>/dev/null)

# --- Memory ------------------------------------------------------------------
mem_total=$(awk '/MemTotal/{print $2}' /proc/meminfo)
mem_avail=$(awk '/MemAvailable/{print $2}' /proc/meminfo)
if [[ -n "$mem_total" && "$mem_total" -gt 0 ]]; then
    mem_pct=$(awk "BEGIN{printf \"%.2f\", (($mem_total-$mem_avail)/$mem_total)*100}")
    echo "nas_memory_usage_pct{host=\"${HOST}\"} ${mem_pct}" >> "${TMP}"
fi

# --- Root disk ---------------------------------------------------------------
root_pct=$(df --output=pcent / | tail -1 | tr -d ' %')
[[ -n "$root_pct" ]] && echo "nas_disk_root_usage_pct{host=\"${HOST}\"} ${root_pct}" >> "${TMP}"

# atomic swap so telegraf never reads a partial file
mv "${TMP}" "${OUT}"
