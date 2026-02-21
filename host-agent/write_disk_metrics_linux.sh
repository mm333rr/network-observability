#!/usr/bin/env bash
# =============================================================================
# write_disk_metrics_linux.sh — Linux equivalent of write_disk_metrics.sh
# Writes disk usage for all mounted volumes to host-metrics/disk_metrics.prom
# Run by cron every 1 minute (see pi-setup.sh)
# Telegraf reads the output via [[inputs.file]]
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${SCRIPT_DIR}/../host-metrics/disk_metrics.prom"
HOST="${HOST_HOSTNAME:-pi}"
TMPFILE="${OUTPUT}.tmp"

{
echo "# HELP disk_usage_percent Disk usage percentage per mount"
echo "# TYPE disk_usage_percent gauge"
echo "# HELP disk_free_bytes Free disk space in bytes per mount"
echo "# TYPE disk_free_bytes gauge"
echo "# HELP disk_total_bytes Total disk size in bytes per mount"
echo "# TYPE disk_total_bytes gauge"

df -B1 --output=target,size,avail,pcent 2>/dev/null \
    | tail -n +2 \
    | grep -vE "^(tmpfs|devtmpfs|udev|overlay|shm|/dev/loop)" \
    | while read -r mount total avail pct; do
        used_pct="${pct/\%/}"
        source_label="local"
        # Tag NFS mounts
        mount_type=$(findmnt -n -o FSTYPE "$mount" 2>/dev/null || echo "")
        [[ "$mount_type" == "nfs"* ]] && source_label="nfs"
        echo "disk_usage_percent{mount=\"${mount}\",host=\"${HOST}\",source=\"${source_label}\"} ${used_pct}"
        echo "disk_free_bytes{mount=\"${mount}\",host=\"${HOST}\"} ${avail}"
        echo "disk_total_bytes{mount=\"${mount}\",host=\"${HOST}\"} ${total}"
    done
} > "$TMPFILE" && mv "$TMPFILE" "$OUTPUT"
