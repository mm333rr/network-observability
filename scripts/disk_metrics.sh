#!/usr/bin/env bash
# =============================================================================
# disk_metrics.sh — Exposes macOS volume disk usage as Prometheus text format
# Called by Telegraf [[inputs.exec]] every 30s
# Uses df -g for cleaner macOS parsing (gigabytes), converts to bytes
# =============================================================================

HOST="macpro"

# macOS df: Filesystem 512-blocks Used Available Capacity iused ifree %iused Mounted on
df -k | grep -E "^/dev/" | while IFS= read -r line; do
    # Extract filesystem and mount point cleanly
    fs=$(echo "$line" | awk '{print $1}')
    total_k=$(echo "$line" | awk '{print $2}')
    used_k=$(echo "$line" | awk '{print $3}')
    avail_k=$(echo "$line" | awk '{print $4}')
    pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
    # Mount point is the last field — handles spaces in paths
    mount=$(echo "$line" | awk '{print $NF}')

    # Skip internal macOS APFS system volumes — only care about data volumes
    case "$mount" in
        /System/Volumes/VM|/System/Volumes/Preboot|/System/Volumes/Update|/Volumes/Docker) continue ;;
    esac

    # Clean label: strip leading slash, replace / and spaces with _
    label=$(echo "$mount" | sed 's|^/||; s|/|_|g; s| |_|g')
    [ -z "$label" ] && label="root"

    free_bytes=$(( avail_k * 1024 ))
    total_bytes=$(( total_k * 1024 ))
    used_bytes=$(( used_k * 1024 ))

    echo "disk_usage_percent{mount=\"$mount\",volume=\"$label\",host=\"$HOST\"} $pct"
    echo "disk_free_bytes{mount=\"$mount\",volume=\"$label\",host=\"$HOST\"} $free_bytes"
    echo "disk_total_bytes{mount=\"$mount\",volume=\"$label\",host=\"$HOST\"} $total_bytes"
    echo "disk_used_bytes{mount=\"$mount\",volume=\"$label\",host=\"$HOST\"} $used_bytes"
done
