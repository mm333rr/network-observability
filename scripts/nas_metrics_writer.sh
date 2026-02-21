#!/usr/bin/env bash
# =============================================================================
# nas_metrics_writer.sh — Wrapper for nas_metrics.sh
# Runs on MacPro host via LaunchAgent every 5 minutes.
# Calls nas_metrics.sh (which SSHes into mbuntu) and writes output to
# host-metrics/nas_metrics.prom for Telegraf inputs.file to read.
# =============================================================================

SCRIPT_DIR="/Volumes/4tb-R1/Docker Services/NetworkObservability/scripts"
OUTDIR="/Volumes/4tb-R1/Docker Services/NetworkObservability/host-metrics"
TMPFILE="${OUTDIR}/nas_metrics.prom.tmp"
OUTFILE="${OUTDIR}/nas_metrics.prom"

# Run the metrics collection script
"${SCRIPT_DIR}/nas_metrics.sh" > "$TMPFILE" 2>/dev/null

# Atomic write
mv "$TMPFILE" "$OUTFILE"
