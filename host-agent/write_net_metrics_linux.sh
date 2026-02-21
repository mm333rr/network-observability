#!/usr/bin/env bash
# =============================================================================
# write_net_metrics_linux.sh — Linux equivalent of write_net_metrics.sh
# Writes network interface counters to host-metrics/net_metrics.prom
# Run by cron every 1 minute (see pi-setup.sh)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${SCRIPT_DIR}/../host-metrics/net_metrics.prom"
HOST="${HOST_HOSTNAME:-pi}"
TMPFILE="${OUTPUT}.tmp"

{
echo "# HELP net_bytes_recv_total Bytes received total per interface"
echo "# TYPE net_bytes_recv_total counter"
echo "# HELP net_bytes_sent_total Bytes sent total per interface"
echo "# TYPE net_bytes_sent_total counter"
echo "# HELP net_link_up Interface link state (1=up)"
echo "# TYPE net_link_up gauge"

# Read from /proc/net/dev -- available on all Linux systems
while IFS=: read -r iface stats; do
    iface="${iface// /}"
    # Skip loopback and virtual interfaces
    [[ "$iface" =~ ^(lo|docker|br-|veth|virbr) ]] && continue
    [[ -z "$iface" ]] && continue
    read -r rx_bytes _ _ _ _ _ _ _ tx_bytes _ <<< "$stats"
    link_up=0
    [[ -f "/sys/class/net/${iface}/operstate" ]] && \
        [[ "$(cat /sys/class/net/${iface}/operstate 2>/dev/null)" == "up" ]] && link_up=1
    echo "net_bytes_recv_total{interface=\"${iface}\",host=\"${HOST}\"} ${rx_bytes:-0}"
    echo "net_bytes_sent_total{interface=\"${iface}\",host=\"${HOST}\"} ${tx_bytes:-0}"
    echo "net_link_up{interface=\"${iface}\",host=\"${HOST}\"} ${link_up}"
done < <(tail -n +3 /proc/net/dev)
} > "$TMPFILE" && mv "$TMPFILE" "$OUTPUT"
