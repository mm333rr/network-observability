#!/usr/bin/env bash
# =============================================================================
# write_net_metrics.sh — Writes macOS host network interface metrics in
# Prometheus text format for consumption by Telegraf [[inputs.file]].
#
# Run by LaunchAgent (com.capes.net-metrics) every 30s on the Mac host.
# Output: host-metrics/net_metrics.prom
#
# Why this exists: Docker Desktop on macOS runs inside a Linux VM. The
# node-exporter container only sees the VM's network interfaces (eth0, lo,
# tunnel adapters) — never the real Mac interfaces en0 (WiFi) or en1
# (Thunderbolt Ethernet / USB-C Ethernet). This script reads netstat -ib
# directly on the macOS host and writes the .prom file that Telegraf can read.
#
# Metrics produced:
#   net_bytes_recv_total    — bytes received (cumulative, counter)
#   net_bytes_sent_total    — bytes sent (cumulative, counter)
#   net_packets_recv_total  — packets received (cumulative, counter)
#   net_packets_sent_total  — packets sent (cumulative, counter)
#   net_errors_recv_total   — receive errors (cumulative, counter)
#   net_errors_sent_total   — send errors (cumulative, counter)
#   net_drops_recv_total    — receive drops (cumulative, counter)
#   net_link_up             — 1 if interface is Up, 0 if not
#
# Interfaces collected: en0, en1, en2, en3 (physical only)
# Skip: lo, utun*, anpi*, llw*, gif*, stf*, ap*, bridge*
# =============================================================================

OUTDIR="$(dirname "$0")"
TMPFILE="${OUTDIR}/net_metrics.prom.tmp"
OUTFILE="${OUTDIR}/net_metrics.prom"
HOST="macpro"

# Interfaces to collect — add en2/en3 if you ever have more NICs
INTERFACES="en0 en1 en2 en3"

{
  echo "# HELP net_bytes_recv_total Bytes received on interface (macOS host, cumulative)"
  echo "# TYPE net_bytes_recv_total counter"
  echo "# HELP net_bytes_sent_total Bytes sent on interface (macOS host, cumulative)"
  echo "# TYPE net_bytes_sent_total counter"
  echo "# HELP net_packets_recv_total Packets received (macOS host, cumulative)"
  echo "# TYPE net_packets_recv_total counter"
  echo "# HELP net_packets_sent_total Packets sent (macOS host, cumulative)"
  echo "# TYPE net_packets_sent_total counter"
  echo "# HELP net_errors_recv_total Receive errors (macOS host, cumulative)"
  echo "# TYPE net_errors_recv_total counter"
  echo "# HELP net_errors_sent_total Send errors (macOS host, cumulative)"
  echo "# TYPE net_errors_sent_total counter"
  echo "# HELP net_drops_recv_total Receive drops (macOS host, cumulative)"
  echo "# TYPE net_drops_recv_total counter"
  echo "# HELP net_link_up Interface link state: 1=Up, 0=Down/missing (macOS host)"
  echo "# TYPE net_link_up gauge"

  for iface in $INTERFACES; do
    # Check if interface exists at all
    if ! ifconfig "$iface" &>/dev/null 2>&1; then
      echo "net_link_up{interface=\"${iface}\",host=\"${HOST}\"} 0"
      continue
    fi

    # Determine link state: Up flag in ifconfig output
    if ifconfig "$iface" 2>/dev/null | grep -q "status: active\|flags=.*<.*UP.*>"; then
      link_up=1
    else
      link_up=0
    fi
    echo "net_link_up{interface=\"${iface}\",host=\"${HOST}\"} ${link_up}"

    # netstat -ib output columns (macOS):
    # Name Mtu Network Address Ipkts Ierrs Ibytes Opkts Oerrs Obytes Drop
    # We need rows where $1 == iface exactly (netstat repeats per address family)
    # Take first matching row only (IPv4 row is sufficient for counters)
    read -r ibytes opkts oerrs obytes drop ipkts ierrs < <(
      netstat -ib -I "$iface" 2>/dev/null \
        | awk -v iface="$iface" 'NR>1 && $1==iface {print $7, $5, $6, $10, $11, $5, $6; exit}'
    )

    # netstat -ib actual columns (macOS Ventura/Sonoma):
    # 1:Name 2:Mtu 3:Network 4:Address 5:Ipkts 6:Ierrs 7:Ibytes 8:Opkts 9:Oerrs 10:Obytes 11:Drop
    # Re-parse cleanly:
    stats=$(netstat -ib -I "$iface" 2>/dev/null | awk -v iface="$iface" '
      NR>1 && $1==iface {
        print $7, $5, $6, $10, $8, $9, $11
        exit
      }
    ')

    ibytes=$(echo "$stats" | awk '{print $1}')
    ipkts=$(echo  "$stats" | awk '{print $2}')
    ierrs=$(echo  "$stats" | awk '{print $3}')
    obytes=$(echo "$stats" | awk '{print $4}')
    opkts=$(echo  "$stats" | awk '{print $5}')
    oerrs=$(echo  "$stats" | awk '{print $6}')
    drops=$(echo  "$stats" | awk '{print $7}')

    # Default to 0 if any field is empty or non-numeric
    ibytes=${ibytes:-0}; ipkts=${ipkts:-0}; ierrs=${ierrs:-0}
    obytes=${obytes:-0}; opkts=${opkts:-0}; oerrs=${oerrs:-0}; drops=${drops:-0}
    # Strip non-numeric chars (dash = 0 in netstat)
    ibytes=$(echo "$ibytes" | tr -cd '0-9'); ibytes=${ibytes:-0}
    obytes=$(echo "$obytes" | tr -cd '0-9'); obytes=${obytes:-0}
    ipkts=$(echo  "$ipkts"  | tr -cd '0-9'); ipkts=${ipkts:-0}
    opkts=$(echo  "$opkts"  | tr -cd '0-9'); opkts=${opkts:-0}
    ierrs=$(echo  "$ierrs"  | tr -cd '0-9'); ierrs=${ierrs:-0}
    oerrs=$(echo  "$oerrs"  | tr -cd '0-9'); oerrs=${oerrs:-0}
    drops=$(echo  "$drops"  | tr -cd '0-9'); drops=${drops:-0}

    echo "net_bytes_recv_total{interface=\"${iface}\",host=\"${HOST}\"} ${ibytes}"
    echo "net_bytes_sent_total{interface=\"${iface}\",host=\"${HOST}\"} ${obytes}"
    echo "net_packets_recv_total{interface=\"${iface}\",host=\"${HOST}\"} ${ipkts}"
    echo "net_packets_sent_total{interface=\"${iface}\",host=\"${HOST}\"} ${opkts}"
    echo "net_errors_recv_total{interface=\"${iface}\",host=\"${HOST}\"} ${ierrs}"
    echo "net_errors_sent_total{interface=\"${iface}\",host=\"${HOST}\"} ${oerrs}"
    echo "net_drops_recv_total{interface=\"${iface}\",host=\"${HOST}\"} ${drops}"
  done
} > "$TMPFILE"

# Atomic write — prevents Telegraf from reading a partial file mid-write
mv "$TMPFILE" "$OUTFILE"
