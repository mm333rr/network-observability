#!/usr/bin/env bash
# =============================================================================
# orbi_metrics.sh — Netgear Orbi RBR750 router metrics via SOAP API
# Version: 2.0.0  (2026-02-19)
#
# Auth method: HTTPS SOAP API with HTTP Basic Auth (per-request, stateless).
#   The Orbi's web UI (HTTP port 80) requires JS-driven session cookie auth
#   that doesn't work headlessly.  The SOAP endpoint on HTTPS port 443 accepts
#   standard HTTP Basic Auth on every call — no session management required.
#
# SOAP endpoint: https://192.168.1.1/soap/server_sa/
#   Verified working services:
#     DeviceInfo:1      GetInfo, GetAttachDevice, GetAttachDevice2, GetSystemInfo
#     WANIPConnection:1 GetInfo  (WAN IP, gateway, DNS, MTU, conn type)
#     WLANConfiguration:1/2  GetInfo  (SSID, channel, mode, security)
#     DeviceConfig:1    GetInfo  (timezone, block-site settings)
#
# Satellite identification:
#   The ConnAPMAC field in GetAttachDevice2 shows which Orbi node each
#   device is connected to.  Nodes other than the router MAC are satellites.
#   Router MAC: C8:9E:43:44:24:CE
#   Known satellite: 10:0C:6B:F1:AE:C5  (bedroom/office area)
#
# Credentials:
#   Master copy in macOS Keychain (interactive shells).
#   Fallback: ROUTER_PASS env var (set by Telegraf via .env file).
#   Fallback: ROUTER_PASS in .env file adjacent to scripts/.
#   See .env for the ROUTER_PASS variable.
#
# Output: Prometheus text format → consumed by Telegraf [[inputs.exec]]
# Called every 30s by Telegraf on the Mac Pro host.
# =============================================================================

set -uo pipefail

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
ROUTER_IP="192.168.1.1"
ROUTER_USER="admin"
HOST_LABEL="macpro"
ROUTER_LABEL="orbi-rbr750"
ROUTER_MAC="C8:9E:43:44:24:CE"   # Main router AP MAC (from WLAN info)

# ---------------------------------------------------------------------------
# Credential resolution
# ---------------------------------------------------------------------------
if [[ -z "${ROUTER_PASS:-}" ]]; then
    ROUTER_PASS=$(security find-internet-password \
        -s "$ROUTER_IP" -a "$ROUTER_USER" -w \
        "/Users/mProAdmin/Library/Keychains/login.keychain-db" 2>/dev/null || true)
fi
if [[ -z "${ROUTER_PASS:-}" ]]; then
    ENV_FILE="$(dirname "$0")/../.env"
    if [[ -f "$ENV_FILE" ]]; then
        ROUTER_PASS=$(grep '^ROUTER_PASS=' "$ENV_FILE" | cut -d= -f2- | tr -d '"' || true)
    fi
fi
if [[ -z "${ROUTER_PASS:-}" ]]; then
    echo "# ERROR: Could not retrieve Orbi password" >&2
    echo "# Fix: set ROUTER_PASS env var, or update keychain entry:" >&2
    echo "#   security add-internet-password -U -a admin -s 192.168.1.1 -r http -l 'Orbi RBR750' -w PASS" >&2
    exit 1
fi

B64=$(printf '%s' "${ROUTER_USER}:${ROUTER_PASS}" | base64)

# ---------------------------------------------------------------------------
# Helper: SOAP call — returns full response XML
# ---------------------------------------------------------------------------
soap_call() {
    local service="$1"     # e.g.  DeviceInfo:1
    local action="$2"      # e.g.  GetInfo
    local body="${3:-}"    # inner XML body (optional)
    curl -sk --max-time 10 --connect-timeout 5 \
      -X POST "https://${ROUTER_IP}/soap/server_sa/" \
      -H "SOAPAction: urn:NETGEAR-ROUTER:service:${service}#${action}" \
      -H "Content-Type: text/xml" \
      -H "Authorization: Basic ${B64}" \
      -d "<?xml version=\"1.0\"?>
<SOAP-ENV:Envelope xmlns:SOAP-ENV=\"http://schemas.xmlsoap.org/soap/envelope/\">
<SOAP-ENV:Body>
<M1:${action} xmlns:M1=\"urn:NETGEAR-ROUTER:service:${service}\">${body}</M1:${action}>
</SOAP-ENV:Body>
</SOAP-ENV:Envelope>" 2>/dev/null
}

# ---------------------------------------------------------------------------
# Helper: extract a single XML tag value from SOAP response
# ---------------------------------------------------------------------------
xml_val() {
    local xml="$1"
    local tag="$2"
    echo "$xml" | python3 -c "
import sys, re
xml = sys.stdin.read()
m = re.search(r'<${tag}>(.*?)</${tag}>', xml, re.DOTALL)
print(m.group(1).strip() if m else '')
" 2>/dev/null
}

# ---------------------------------------------------------------------------
# 1. Router reachability (ping before SOAP — fast fail)
# ---------------------------------------------------------------------------
ROUTER_UP=0
if ping -c 1 -W 2 "$ROUTER_IP" &>/dev/null; then
    ROUTER_UP=1
fi
echo "# HELP orbi_up 1 if Orbi node responds to ping"
echo "# TYPE orbi_up gauge"
echo "orbi_up{host=\"${HOST_LABEL}\",node=\"router\",ip=\"${ROUTER_IP}\"} ${ROUTER_UP}"

if [[ "$ROUTER_UP" -eq 0 ]]; then
    echo "# Router unreachable — skipping SOAP metrics"
    exit 0
fi

# ---------------------------------------------------------------------------
# 2. Device info (firmware, model)
# ---------------------------------------------------------------------------
DEV_XML=$(soap_call "DeviceInfo:1" "GetInfo")
FIRMWARE=$(xml_val "$DEV_XML" "Firmwareversion")
FW_OTHER=$(xml_val "$DEV_XML" "OthersoftwareVersion")
MODEL=$(xml_val "$DEV_XML" "ModelName")
FW_LABEL="${FIRMWARE:-unknown}_${FW_OTHER:-unknown}"

echo ""
echo "# HELP orbi_firmware_info Router firmware version (informational, value=1)"
echo "# TYPE orbi_firmware_info gauge"
echo "orbi_firmware_info{host=\"${HOST_LABEL}\",device=\"${ROUTER_LABEL}\",model=\"${MODEL:-RBR750}\",firmware=\"${FW_LABEL}\"} 1"

# ---------------------------------------------------------------------------
# 3. WAN / Internet status
# ---------------------------------------------------------------------------
WAN_XML=$(soap_call "WANIPConnection:1" "GetInfo")
WAN_IP=$(xml_val "$WAN_XML" "NewExternalIPAddress")
WAN_TYPE=$(xml_val "$WAN_XML" "NewConnectionType")
WAN_GW=$(xml_val "$WAN_XML" "NewDefaultGateway")
WAN_DNS=$(xml_val "$WAN_XML" "NewDNSServers")
WAN_ENABLED=$(xml_val "$WAN_XML" "NewEnable")

WAN_CONNECTED=0
if [[ -n "$WAN_IP" && "$WAN_IP" != "0.0.0.0" ]]; then
    WAN_CONNECTED=1
fi

echo ""
echo "# HELP orbi_wan_up 1 if WAN connection is established with a valid public IP"
echo "# TYPE orbi_wan_up gauge"
echo "orbi_wan_up{host=\"${HOST_LABEL}\",device=\"${ROUTER_LABEL}\",wan_ip=\"${WAN_IP:-unknown}\",conn_type=\"${WAN_TYPE:-unknown}\",gateway=\"${WAN_GW:-unknown}\"} ${WAN_CONNECTED}"

# ---------------------------------------------------------------------------
# 4. Router CPU and memory from GetSystemInfo
# ---------------------------------------------------------------------------
SYS_XML=$(soap_call "DeviceInfo:1" "GetSystemInfo")
CPU_PCT=$(xml_val "$SYS_XML" "NewCPUUtilization")
MEM_PCT=$(xml_val "$SYS_XML" "NewMemoryUtilization")
MEM_MB=$(xml_val "$SYS_XML" "NewPhysicalMemory")

echo ""
echo "# HELP orbi_cpu_utilization_pct Router CPU utilization percent"
echo "# TYPE orbi_cpu_utilization_pct gauge"
echo "orbi_cpu_utilization_pct{host=\"${HOST_LABEL}\",device=\"${ROUTER_LABEL}\"} ${CPU_PCT:-0}"

echo ""
echo "# HELP orbi_memory_utilization_pct Router RAM utilization percent"
echo "# TYPE orbi_memory_utilization_pct gauge"
echo "orbi_memory_utilization_pct{host=\"${HOST_LABEL}\",device=\"${ROUTER_LABEL}\",total_mb=\"${MEM_MB:-256}\"} ${MEM_PCT:-0}"

# ---------------------------------------------------------------------------
# 5. WiFi radio info (band, SSID, channel, security)
# ---------------------------------------------------------------------------
WLAN1_XML=$(soap_call "WLANConfiguration:1" "GetInfo")
SSID=$(xml_val "$WLAN1_XML" "NewSSID")
CHANNEL=$(xml_val "$WLAN1_XML" "NewChannel")
MODE=$(xml_val "$WLAN1_XML" "NewWirelessMode")
SECURITY=$(xml_val "$WLAN1_XML" "NewBasicEncryptionModes")
RADIO_STATUS=$(xml_val "$WLAN1_XML" "NewStatus")
RADIO_UP=0
[[ "$RADIO_STATUS" == "Up" ]] && RADIO_UP=1

echo ""
echo "# HELP orbi_radio_up 1 if the wireless radio is Up"
echo "# TYPE orbi_radio_up gauge"
echo "orbi_radio_up{host=\"${HOST_LABEL}\",device=\"${ROUTER_LABEL}\",ssid=\"${SSID:-unknown}\"} ${RADIO_UP}"

echo ""
echo "# HELP orbi_radio_info Wireless configuration details (informational, value=1)"
echo "# TYPE orbi_radio_info gauge"
echo "orbi_radio_info{host=\"${HOST_LABEL}\",device=\"${ROUTER_LABEL}\",ssid=\"${SSID:-unknown}\",channel=\"${CHANNEL:-auto}\",mode=\"${MODE:-unknown}\",security=\"${SECURITY:-unknown}\"} 1"

# ---------------------------------------------------------------------------
# 6. Connected devices — per-device RSSI, linkspeed, band, AP node
#    Uses GetAttachDevice2 which provides richer per-device data including
#    ConnAPMAC (which Orbi node the device is connected to)
# ---------------------------------------------------------------------------
DEV2_XML=$(soap_call "DeviceInfo:1" "GetAttachDevice2")

# Parse with Python — write XML to temp file to avoid heredoc/stdin piping issues
PARSE_TMP=$(mktemp /tmp/orbi_dev2_XXXXXX.xml)
echo "$DEV2_XML" > "$PARSE_TMP"

DEVICE_METRICS=$(python3 /dev/stdin "$PARSE_TMP" "$ROUTER_MAC" "$HOST_LABEL" "$ROUTER_LABEL" <<'PYEOF'
import sys, re

xml_file = sys.argv[1]
ROUTER_MAC = sys.argv[2].upper()
HOST = sys.argv[3]
DEVICE = sys.argv[4]

with open(xml_file) as f:
    xml = f.read()

devices = re.findall(r'<Device>(.*?)</Device>', xml, re.DOTALL)

total = len(devices)
wired = 0
wireless_24 = 0
wireless_5 = 0
ap_device_counts = {}
rssi_lines = []
speed_lines = []

for dev in devices:
    def tag(t):
        m = re.search(fr'<{t}>(.*?)</{t}>', dev, re.DOTALL)
        return m.group(1).strip() if m else ''

    ip = tag('IP')
    name = re.sub(r'[^a-zA-Z0-9_\-]', '_', tag('Name') or tag('n'))[:32]
    mac = tag('MAC')
    conn = tag('ConnectionType')
    rssi = tag('SignalStrength')
    linkspeed = tag('Linkspeed')
    dev_type = tag('DeviceTypeV2')
    brand = tag('DeviceBrand')
    ap_mac = tag('ConnAPMAC').upper()

    node = "router" if ap_mac == ROUTER_MAC else (
        f"satellite_{ap_mac.replace(':','').lower()}" if ap_mac else "unknown"
    )
    ap_device_counts[node] = ap_device_counts.get(node, 0) + 1

    if conn == 'wired':
        wired += 1
    elif '2.4' in conn:
        wireless_24 += 1
    elif '5' in conn:
        wireless_5 += 1

    if conn != 'wired' and rssi:
        rssi_lines.append(
            f'orbi_device_rssi{{host="{HOST}",name="{name}",'
            f'ip="{ip}",mac="{mac}",band="{conn}",'
            f'type="{dev_type}",brand="{brand}",node="{node}"}} {rssi}'
        )
    if conn != 'wired' and linkspeed:
        speed_lines.append(
            f'orbi_device_linkspeed_mbps{{host="{HOST}",name="{name}",'
            f'ip="{ip}",mac="{mac}",band="{conn}",node="{node}"}} {linkspeed}'
        )

print(f'# HELP orbi_devices_total Total devices connected to Orbi mesh')
print(f'# TYPE orbi_devices_total gauge')
print(f'orbi_devices_total{{host="{HOST}",device="{DEVICE}"}} {total}')
print()
print(f'# HELP orbi_devices_by_connection Devices by connection type')
print(f'# TYPE orbi_devices_by_connection gauge')
print(f'orbi_devices_by_connection{{host="{HOST}",conn_type="wired"}} {wired}')
print(f'orbi_devices_by_connection{{host="{HOST}",conn_type="2.4GHz"}} {wireless_24}')
print(f'orbi_devices_by_connection{{host="{HOST}",conn_type="5GHz"}} {wireless_5}')
print()
print(f'# HELP orbi_node_device_count Devices connected to each Orbi mesh node')
print(f'# TYPE orbi_node_device_count gauge')
for node, count in sorted(ap_device_counts.items()):
    print(f'orbi_node_device_count{{host="{HOST}",node="{node}"}} {count}')
print()
print(f'# HELP orbi_device_rssi Per-device WiFi signal strength (0-100 Orbi scale)')
print(f'# TYPE orbi_device_rssi gauge')
for l in rssi_lines:
    print(l)
print()
print(f'# HELP orbi_device_linkspeed_mbps Per-device negotiated link speed in Mbps')
print(f'# TYPE orbi_device_linkspeed_mbps gauge')
for l in speed_lines:
    print(l)
PYEOF
)
rm -f "$PARSE_TMP"

echo ""
echo "$DEVICE_METRICS"

# ---------------------------------------------------------------------------
# 7. Satellite node reachability via ping
#    Satellites show up as AP MACs distinct from the router MAC.
#    We derive their IPs from wired devices on those APs (wired backhaul clients).
#    As a practical proxy: ping well-known satellite IP range or any wired-non-router device.
# ---------------------------------------------------------------------------

# Known satellite MACs → IPs can be found from the device list as ConnAPMAC owners.
# The satellite itself (RBS node) connects its Ethernet/backhaul and won't appear
# as a DHCP client. We ping the satellite's assumed management IP by deriving from
# the connected devices. Simplest: ping the discovered satellite AP MAC via arp.

echo ""
echo "# HELP orbi_satellite_up 1 if satellite Orbi node responds to ping"
echo "# TYPE orbi_satellite_up gauge"

# Discover satellite IPs via arp cache (satellites have known OUI 10:0C:6B or C8:9E:43)
SAT_IPS=$(arp -an 2>/dev/null | python3 -c "
import sys, re
ROUTER_MAC = 'c8:9e:43:44:24:ce'
lines = sys.stdin.readlines()
for line in lines:
    # arp -an format: ? (192.168.1.1) at c8:9e:43:44:24:ce on en0 ...
    m = re.search(r'\((\d+\.\d+\.\d+\.\d+)\) at ([0-9a-f:]+)', line)
    if m:
        ip, mac = m.group(1), m.group(2).lower()
        # Orbi RBR/RBS OUIs: c8:9e:43, 10:0c:6b, 9c:3d:cf, 9c:ef:d5
        if any(mac.startswith(oui) for oui in ['c8:9e:43','10:0c:6b','9c:3d:cf','9c:ef:d5']):
            if mac != ROUTER_MAC:
                name = 'satellite_' + mac.replace(':','')
                print(f'{ip} {name}')
" 2>/dev/null)

if [[ -n "$SAT_IPS" ]]; then
    while IFS=' ' read -r sat_ip sat_name; do
        [[ -z "$sat_ip" ]] && continue
        sat_up=0
        if ping -c 1 -W 2 "$sat_ip" &>/dev/null; then
            sat_up=1
        fi
        echo "orbi_satellite_up{host=\"${HOST_LABEL}\",satellite_ip=\"${sat_ip}\",satellite_name=\"${sat_name}\"} ${sat_up}"
    done <<< "$SAT_IPS"
else
    echo "# No satellites detected in arp cache (may be online but not in arp table)"
    echo "orbi_satellite_up{host=\"${HOST_LABEL}\",satellite_ip=\"none\",satellite_name=\"none\"} 0"
fi

# ---------------------------------------------------------------------------
# 8. Internet latency (ping RTT to router, Cloudflare, Google)
# ---------------------------------------------------------------------------
echo ""
echo "# HELP orbi_ping_rtt_ms Round-trip latency in milliseconds (3-ping avg)"
echo "# TYPE orbi_ping_rtt_ms gauge"

_ping_rtt() {
    local target="$1"
    ping -c 3 -q "$target" 2>/dev/null \
      | grep -E "round-trip|rtt" \
      | awk -F'[/= ]' '{
          for(i=1;i<=NF;i++){
            if($i ~ /^[0-9]+\.[0-9]+$/ && prev ~ /min/){print $i; exit}
            prev=$i
          }
        }' \
      | awk 'NR==2{print; exit} NR==1{prev=$0} END{if(!NR)print prev}' 2>/dev/null \
    || echo "-1"
}

# macOS ping format: round-trip min/avg/max/stddev = 1.234/2.345/3.456/0.123 ms
RTT_ROUTER=$(ping -c 3 -q "$ROUTER_IP" 2>/dev/null | grep "round-trip" | awk -F'/' '{print $5}' || echo "-1")
RTT_CF=$(ping -c 3 -q "1.1.1.1" 2>/dev/null | grep "round-trip" | awk -F'/' '{print $5}' || echo "-1")
RTT_G=$(ping -c 3 -q "8.8.8.8" 2>/dev/null | grep "round-trip" | awk -F'/' '{print $5}' || echo "-1")

echo "orbi_ping_rtt_ms{host=\"${HOST_LABEL}\",target=\"router\",target_ip=\"${ROUTER_IP}\"} ${RTT_ROUTER:--1}"
echo "orbi_ping_rtt_ms{host=\"${HOST_LABEL}\",target=\"cloudflare\",target_ip=\"1.1.1.1\"} ${RTT_CF:--1}"
echo "orbi_ping_rtt_ms{host=\"${HOST_LABEL}\",target=\"google\",target_ip=\"8.8.8.8\"} ${RTT_G:--1}"

# ---------------------------------------------------------------------------
# 9. DNS resolution latency
# ---------------------------------------------------------------------------
echo ""
echo "# HELP orbi_dns_resolve_ms DNS resolution time in milliseconds (0=failed)"
echo "# TYPE orbi_dns_resolve_ms gauge"

DNS_MS=$(python3 -c "
import socket, time
start = time.time()
try:
    socket.getaddrinfo('cloudflare.com', 80)
    print(f'{(time.time()-start)*1000:.1f}')
except:
    print('0')
" 2>/dev/null || echo "0")

echo "orbi_dns_resolve_ms{host=\"${HOST_LABEL}\",resolver=\"system\"} ${DNS_MS}"

# ---------------------------------------------------------------------------
echo ""
echo "# orbi_metrics.sh v2.0.0 complete — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
