#!/bin/bash
# observability-start.sh
# Waits for Docker Desktop to be fully ready, then starts the observability stack.
# Called by com.capes.observability.plist on login.

export PATH="/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

STACK_DIR="/Volumes/4tb-R1/Docker Services/NetworkObservability"
LOG="/tmp/observability-autostart.log"
MAX_WAIT=120  # seconds to wait for Docker to be ready

echo "[$(date)] observability-start: waiting for Docker..." >> "$LOG"

elapsed=0
while ! docker info &>/dev/null; do
    sleep 5
    elapsed=$((elapsed + 5))
    if [ "$elapsed" -ge "$MAX_WAIT" ]; then
        echo "[$(date)] ERROR: Docker not ready after ${MAX_WAIT}s, aborting." >> "$LOG"
        exit 1
    fi
done

echo "[$(date)] Docker ready after ${elapsed}s. Starting observability stack..." >> "$LOG"
cd "$STACK_DIR" && docker compose up -d >> "$LOG" 2>&1
echo "[$(date)] docker compose up -d exit code: $?" >> "$LOG"

# Pre-create .prom files so Telegraf textfile_collector doesn't error on cold boot
# (scripts will overwrite with real data on their first run)
METRICS_DIR="/Volumes/4tb-R1/Docker Services/NetworkObservability/host-metrics"
for f in disk_metrics.prom smart_metrics.prom net_metrics.prom nas_metrics.prom; do
    [ -f "${METRICS_DIR}/${f}" ] || touch "${METRICS_DIR}/${f}"
    echo "[\Fri Feb 20 21:12:30 PST 2026] Ensured ${f} exists" >> "$LOG"
done
