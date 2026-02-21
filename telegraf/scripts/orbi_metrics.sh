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
# Helper: extract a single XML tag value from SOAP response (no python3)
# Uses grep+sed — works in Alpine/Debian containers with no extra deps.
# ---------------------------------------------------------------------------
xml_val() {
    local xml="$1"
    local tag="$2"
    printf '%s' "$xml" \
      | tr -d '\r' \
      | grep -oE "<${tag}>[^<]*</${tag}>" \
      | sed "s|<${tag}>\(.*\)</${tag}>|\1|" \
      | head -1 \
      | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
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

# NOTE: orbi_cpu_utilization_pct is intentionally NOT emitted.
# The RBR750 SOAP GetSystemInfo endpoint returns NewCPUUtilization=100 at all
# times regardless of actual load — confirmed across firmware V7.2.8.2_5.1.18.
# This is a known Netgear firmware reporting bug (Netgear community #2052382).
# Emitting it would permanently fire the OrbiHighCPU alert. Router health is
# better measured via ping RTT to 192.168.1.1 and internet latency (section 8).

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

# Parse device list with awk — no python3 required (works in Alpine containers)
# The XML has one tag per line after normalization; we parse Device blocks.
DEVICE_METRICS=$(printf '%s' "$DEV2_XML" | tr -d '\r' | awk \
  -v ROUTER_MAC="${ROUTER_MAC}" \
  -v HOST="${HOST_LABEL}" \
  -v DEVICE="${ROUTER_LABEL}" '
function tag_val(xml, t,    pat, val) {
    pat = "<" t ">([^<]*)</" t ">"
    if (match(xml, "<" t ">[^<]*</" t ">")) {
        val = substr(xml, RSTART + length(t) + 2, RLENGTH - length(t)*2 - 5)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
        return val
    }
    return ""
}
function safe_name(s,    r) {
    r = s
    gsub(/[^a-zA-Z0-9_-]/, "_", r)
    if (length(r) > 32) r = substr(r, 1, 32)
    return r
}
function upper(s,    r, i, c) {
    r = s
    for (i = 1; i <= length(r); i++) {
        c = substr(r, i, 1)
        if (c >= "a" && c <= "z") {
            r = substr(r, 1, i-1) sprintf("%c", ord[c]) substr(r, i+1)
        }
    }
    return r
}
BEGIN {
    # Build ord map for uppercase
    for (i = 97; i <= 122; i++) ord[sprintf("%c",i)] = i - 32
    in_dev = 0; dev = ""
    total = 0; wired = 0; g24 = 0; g5 = 0
    rssi_out = ""; speed_out = ""; node_counts = ""
    split("", node_cnt)
}
/<Device>/ { in_dev = 1; dev = ""; next }
/<\/Device>/ {
    in_dev = 0
    ip   = tag_val(dev, "IP")
    nm   = safe_name(tag_val(dev, "Name"))
    mac  = tag_val(dev, "MAC")
    conn = tag_val(dev, "ConnectionType")
    rssi = tag_val(dev, "SignalStrength")
    lspd = tag_val(dev, "Linkspeed")
    dtyp = tag_val(dev, "DeviceTypeV2")
    bran = tag_val(dev, "DeviceBrand")
    apm  = tag_val(dev, "ConnAPMAC")
    gsub(/:/, "", apm); apm_low = tolower(apm)
    router_mac_no_colon = ROUTER_MAC; gsub(/:/, "", router_mac_no_colon)
    if (tolower(apm_low) == tolower(router_mac_no_colon)) {
        node = "router"
    } else if (apm_low != "") {
        node = "satellite_" apm_low
    } else {
        node = "unknown"
    }
    node_cnt[node]++
    total++
    if (conn == "wired") wired++
    else if (index(conn, "2.4") > 0) g24++
    else if (index(conn, "5") > 0) g5++
    if (conn != "wired" && rssi != "") {
        rssi_out = rssi_out "orbi_device_rssi{host=\"" HOST "\",name=\"" nm "\",ip=\"" ip "\",mac=\"" mac "\",band=\"" conn "\",type=\"" dtyp "\",brand=\"" bran "\",node=\"" node "\"} " rssi "\n"
    }
    if (conn != "wired" && lspd != "") {
        speed_out = speed_out "orbi_device_linkspeed_mbps{host=\"" HOST "\",name=\"" nm "\",ip=\"" ip "\",mac=\"" mac "\",band=\"" conn "\",node=\"" node "\"} " lspd "\n"
    }
    next
}
in_dev { dev = dev $0 "\n"; next }
END {
    print "# HELP orbi_devices_total Total devices connected to Orbi mesh"
    print "# TYPE orbi_devices_total gauge"
    print "orbi_devices_total{host=\"" HOST "\",device=\"" DEVICE "\"} " total
    print ""
    print "# HELP orbi_devices_by_connection Devices by connection type"
    print "# TYPE orbi_devices_by_connection gauge"
    print "orbi_devices_by_connection{host=\"" HOST "\",conn_type=\"wired\"} " wired
    print "orbi_devices_by_connection{host=\"" HOST "\",conn_type=\"2.4GHz\"} " g24
    print "orbi_devices_by_connection{host=\"" HOST "\",conn_type=\"5GHz\"} " g5
    print ""
    print "# HELP orbi_node_device_count Devices connected to each Orbi mesh node"
    print "# TYPE orbi_node_device_count gauge"
    for (n in node_cnt) print "orbi_node_device_count{host=\"" HOST "\",node=\"" n "\"} " node_cnt[n]
    print ""
    print "# HELP orbi_device_rssi Per-device WiFi signal strength (0-100 Orbi scale)"
    print "# TYPE orbi_device_rssi gauge"
    printf "%s", rssi_out
    print ""
    print "# HELP orbi_device_linkspeed_mbps Per-device negotiated link speed in Mbps"
    print "# TYPE orbi_device_linkspeed_mbps gauge"
    printf "%s", speed_out
}')
: # device parsing complete

echo ""
echo "$DEVICE_METRICS"

# ---------------------------------------------------------------------------
# 7. Satellite node reachability — derived from active client count
#
# Orbi RBS750 satellites do not get a pingable LAN IP (they use a dedicated
# backhaul subnet not exposed to DHCP/ARP) and no Netgear SOAP endpoint
# exposes satellite IPs. The most reliable proxy: if devices are actively
# connected TO a satellite's AP MAC (ConnAPMAC field), the satellite is up.
#
# We parse orbi_node_device_count lines already emitted by the awk block
# and emit orbi_satellite_up=1 for any satellite with >=1 connected device.
# Known satellite MACs with 0 connections emit orbi_satellite_up=0.
#
# Known satellites: 10:0C:6B:F1:AE:C5 (bedroom/office RBS750)
# ---------------------------------------------------------------------------

echo ""
echo "# HELP orbi_satellite_up 1 if satellite mesh node has active connected clients"
echo "# TYPE orbi_satellite_up gauge"

# Remaining known MACs that haven't appeared in DEVICE_METRICS output
REMAINING_SATS=("100c6bf1aec5")

while IFS= read -r line; do
    [[ "$line" =~ orbi_node_device_count.*node=\"(satellite_([^\"]+))\".*[[:space:]]([0-9]+) ]] || continue
    node="${BASH_REMATCH[1]}"
    mac="${BASH_REMATCH[2]}"
    count="${BASH_REMATCH[3]}"
    sat_up=0; [[ "$count" -gt 0 ]] && sat_up=1
    echo "orbi_satellite_up{host=\"${HOST_LABEL}\",satellite_mac=\"${mac}\",satellite_node=\"${node}\"} ${sat_up}"
    REMAINING_SATS=("${REMAINING_SATS[@]/$mac}")
done <<< "$DEVICE_METRICS"

# Any known satellite not seen in device list at all → emit 0 (fully disconnected)
for mac in "${REMAINING_SATS[@]}"; do
    [[ -z "$mac" ]] && continue
    echo "orbi_satellite_up{host=\"${HOST_LABEL}\",satellite_mac=\"${mac}\",satellite_node=\"satellite_${mac}\"} 0"
done

# ---------------------------------------------------------------------------
# 8. Internet latency (ping RTT to router, Cloudflare, Google)
# ---------------------------------------------------------------------------
echo ""
echo "# HELP orbi_ping_rtt_ms Round-trip latency in milliseconds (3-ping avg)"
echo "# TYPE orbi_ping_rtt_ms gauge"

# macOS: "round-trip min/avg/max/stddev = 1.2/2.3/3.4/0.1 ms" → field 5 after /
# Linux:  "rtt min/avg/max/mdev = 1.2/2.3/3.4/0.1 ms"         → field 5 after /
_ping_avg() {
    local target="$1"
    ping -c 3 -q "$target" 2>/dev/null \
      | grep -E "^(rtt|round-trip)" \
      | awk -F'/' '{print $5}' \
    || echo "-1"
}

RTT_ROUTER=$(_ping_avg "$ROUTER_IP")
RTT_CF=$(_ping_avg "1.1.1.1")
RTT_G=$(_ping_avg "8.8.8.8")

echo "orbi_ping_rtt_ms{host=\"${HOST_LABEL}\",target=\"router\",target_ip=\"${ROUTER_IP}\"} ${RTT_ROUTER:--1}"
echo "orbi_ping_rtt_ms{host=\"${HOST_LABEL}\",target=\"cloudflare\",target_ip=\"1.1.1.1\"} ${RTT_CF:--1}"
echo "orbi_ping_rtt_ms{host=\"${HOST_LABEL}\",target=\"google\",target_ip=\"8.8.8.8\"} ${RTT_G:--1}"

# ---------------------------------------------------------------------------
# 9. DNS resolution latency
# ---------------------------------------------------------------------------
echo ""
echo "# HELP orbi_dns_resolve_ms DNS resolution time in milliseconds (0=failed)"
echo "# TYPE orbi_dns_resolve_ms gauge"

DNS_MS=$(
    START=$(date +%s%3N 2>/dev/null || date +%s)
    nslookup cloudflare.com >/dev/null 2>&1 || getent hosts cloudflare.com >/dev/null 2>&1 || true
    END=$(date +%s%3N 2>/dev/null || date +%s)
    echo $((END - START))
)

echo "orbi_dns_resolve_ms{host=\"${HOST_LABEL}\",resolver=\"system\"} ${DNS_MS}"

# ---------------------------------------------------------------------------
echo ""
echo "# orbi_metrics.sh v2.0.0 complete — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
