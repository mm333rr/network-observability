#!/usr/bin/env bash
# =============================================================================
# write_disk_metrics.sh — Writes macOS disk metrics in Prometheus text format
# Run by LaunchAgent (com.capes.disk-metrics) every 30s on the Mac host.
# Output goes to host-metrics/disk_metrics.prom, read by Telegraf inputs.file.
#
# Why this exists: Docker on macOS cannot see individual APFS volume stats via
# df inside the container — all bind-mounted volumes appear as one filesystem.
# Running df on the real macOS host and writing a prom file is the reliable fix.
# =============================================================================

OUTDIR="$(dirname "$0")"
TMPFILE="${OUTDIR}/disk_metrics.prom.tmp"
OUTFILE="${OUTDIR}/disk_metrics.prom"
HOST="macpro"

{
  echo "# HELP disk_free_bytes Free disk space in bytes (macOS host)"
  echo "# TYPE disk_free_bytes gauge"
  echo "# HELP disk_total_bytes Total disk size in bytes (macOS host)"
  echo "# TYPE disk_total_bytes gauge"
  echo "# HELP disk_used_bytes Used disk space in bytes (macOS host)"
  echo "# TYPE disk_used_bytes gauge"
  echo "# HELP disk_usage_percent Disk usage percentage (macOS host)"
  echo "# TYPE disk_usage_percent gauge"

  df -k | grep -E "^/dev/" | while IFS= read -r line; do
    fs=$(echo "$line" | awk '{print $1}')
    total_k=$(echo "$line" | awk '{print $2}')
    used_k=$(echo "$line" | awk '{print $3}')
    avail_k=$(echo "$line" | awk '{print $4}')
    pct=$(echo "$line" | awk '{print $5}' | tr -d '%')
    mount=$(echo "$line" | awk '{print $NF}')

    # Skip internal macOS system volumes
    case "$mount" in
      /System/Volumes/VM|/System/Volumes/Preboot|/System/Volumes/Update|/Volumes/Docker) continue ;;
    esac

    label=$(echo "$mount" | sed 's|^/||; s|/|_|g; s| |_|g')
    [ -z "$label" ] && label="root"

    free_bytes=$(( avail_k * 1024 ))
    total_bytes=$(( total_k * 1024 ))
    used_bytes=$(( used_k * 1024 ))

    echo "disk_free_bytes{mount=\"${mount}\",volume=\"${label}\",host=\"${HOST}\"} ${free_bytes}"
    echo "disk_total_bytes{mount=\"${mount}\",volume=\"${label}\",host=\"${HOST}\"} ${total_bytes}"
    echo "disk_used_bytes{mount=\"${mount}\",volume=\"${label}\",host=\"${HOST}\"} ${used_bytes}"
    echo "disk_usage_percent{mount=\"${mount}\",volume=\"${label}\",host=\"${HOST}\"} ${pct}"
  done
} > "$TMPFILE"

# Atomic write — prevents Telegraf from reading a partial file
mv "$TMPFILE" "$OUTFILE"
