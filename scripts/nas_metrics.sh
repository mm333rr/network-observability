#!/usr/bin/env bash
# =============================================================================
# nas_metrics.sh — Collects ZFS, SMART, and system metrics from Ubuntu NAS
# Target: mbuntu (192.168.1.35) via SSH key auth
# Run by: LaunchAgent com.capes.nas-metrics every 5 minutes
# Output: Prometheus text format → host-metrics/nas_metrics.prom → Telegraf
#
# Metrics: nas_up, nas_zpool_*, nas_zfs_dataset_*, nas_smart_*,
#          nas_cpu_usage_pct, nas_memory_usage_pct, nas_disk_root_usage_pct,
#          nas_uptime_seconds, nas_nfs_exports_count, nas_docker_containers_running
# =============================================================================

SSH_HOST="mbuntu"
LABELS='host="mbuntu",location="capes-ventura"'

# Collect all data in a single SSH session
RAW=$(ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$SSH_HOST" bash 2>/dev/null <<'REMOTESCRIPT'
echo "===ZPOOL==="
zpool list -Hp 2>/dev/null || echo "FAIL"
echo "===STATUS==="
zpool status tank 2>/dev/null | grep -E "^\s+(sd[a-z]|raidz)" || echo "FAIL"
echo "===SCRUB==="
zpool status tank 2>/dev/null | grep "scan:" | head -1
echo "===ZFS==="
zfs list -Hpo name,used,avail,refer -r tank 2>/dev/null || echo "FAIL"
echo "===SMART==="
for d in /dev/sd[a-z]; do
  [ -b "$d" ] || continue
  n=$(basename "$d")
  h=$(sudo smartctl -H "$d" 2>/dev/null | grep -ioE "passed|PASSED|ok|OK|failed|FAILED" | head -1)
  t=$(sudo smartctl -A "$d" 2>/dev/null | grep -i "temperature" | head -1 | awk '{print $10}')
  echo "$n ${h:-unknown} ${t:-0}"
done
echo "===SYS==="
# CPU idle
top -bn1 2>/dev/null | grep "^%Cpu" | awk '{print $8}' | head -1
# Memory
free 2>/dev/null | awk '/^Mem:/{printf "%.1f\n", ($3/$2)*100}'
# Root disk %
df / 2>/dev/null | tail -1 | awk '{gsub(/%/,""); print $5}'
# Uptime seconds
awk '{printf "%d\n", $1}' /proc/uptime 2>/dev/null
# NFS exports
grep -c '^/' /etc/exports 2>/dev/null || echo 0
# Docker containers
docker ps -q 2>/dev/null | wc -l | tr -d ' '
echo "===END==="
REMOTESCRIPT
)

if [ -z "$RAW" ]; then
  echo "nas_up{${LABELS}} 0"
  exit 0
fi

echo "nas_up{${LABELS}} 1"

# --- Parse zpool list ---
ZPOOL_LINE=$(echo "$RAW" | sed -n '/===ZPOOL===/,/===STATUS===/p' | grep -v "===" | grep -v "FAIL" | head -1)
if [ -n "$ZPOOL_LINE" ]; then
  read -r name size alloc free _ _ frag cap _ health _ <<< "$ZPOOL_LINE"
  PL="${LABELS},pool=\"${name}\""
  case "$health" in ONLINE) hv=1;; *) hv=0;; esac
  echo "nas_zpool_health{${PL}} ${hv}"
  echo "nas_zpool_size_bytes{${PL}} ${size}"
  echo "nas_zpool_alloc_bytes{${PL}} ${alloc}"
  echo "nas_zpool_free_bytes{${PL}} ${free}"
  echo "nas_zpool_capacity_pct{${PL}} ${cap}"
  echo "nas_zpool_fragmentation_pct{${PL}} ${frag}"
fi

# --- Parse vdev errors ---
echo "$RAW" | sed -n '/===STATUS===/,/===SCRUB===/p' | grep -v "===" | grep -v "FAIL" | while read -r vdev state re we ce; do
  [ -z "$vdev" ] && continue
  VL="${LABELS},pool=\"tank\",vdev=\"${vdev}\""
  echo "nas_zpool_read_errors{${VL}} ${re:-0}"
  echo "nas_zpool_write_errors{${VL}} ${we:-0}"
  echo "nas_zpool_cksum_errors{${VL}} ${ce:-0}"
done

# --- Parse ZFS datasets ---
echo "$RAW" | sed -n '/===ZFS===/,/===SMART===/p' | grep -v "===" | grep -v "FAIL" | sort -u | while IFS=$'\t' read -r name used avail refer; do
  [ -z "$name" ] && continue
  DL="${LABELS},dataset=\"${name}\""
  echo "nas_zfs_dataset_used_bytes{${DL}} ${used}"
  echo "nas_zfs_dataset_avail_bytes{${DL}} ${avail}"
  echo "nas_zfs_dataset_refer_bytes{${DL}} ${refer}"
done

# --- Parse SMART ---
echo "$RAW" | sed -n '/===SMART===/,/===SYS===/p' | grep -v "===" | while read -r dev health temp; do
  [ -z "$dev" ] && continue
  SL="${LABELS},disk=\"${dev}\""
  case "$health" in passed|PASSED|ok|OK) sv=1;; failed|FAILED) sv=0;; *) sv=-1;; esac
  echo "nas_smart_health{${SL}} ${sv}"
  [ -n "$temp" ] && [ "$temp" != "0" ] && echo "nas_smart_temperature_celsius{${SL}} ${temp}"
done

# --- Parse system metrics ---
SYS_LINES=$(echo "$RAW" | sed -n '/===SYS===/,/===END===/p' | grep -v "===")
cpu_idle=$(echo "$SYS_LINES" | sed -n '1p')
mem_pct=$(echo "$SYS_LINES" | sed -n '2p')
root_pct=$(echo "$SYS_LINES" | sed -n '3p')
uptime_s=$(echo "$SYS_LINES" | sed -n '4p')
nfs_n=$(echo "$SYS_LINES" | sed -n '5p')
docker_n=$(echo "$SYS_LINES" | sed -n '6p')

if [ -n "$cpu_idle" ]; then
  cpu_used=$(python3 -c "print(round(100 - float('${cpu_idle}'), 1))" 2>/dev/null || echo "0")
  echo "nas_cpu_usage_pct{${LABELS}} ${cpu_used}"
fi
[ -n "$mem_pct" ] && echo "nas_memory_usage_pct{${LABELS}} ${mem_pct}"
[ -n "$root_pct" ] && echo "nas_disk_root_usage_pct{${LABELS}} ${root_pct}"
[ -n "$uptime_s" ] && echo "nas_uptime_seconds{${LABELS}} ${uptime_s}"
[ -n "$nfs_n" ] && echo "nas_nfs_exports_count{${LABELS}} ${nfs_n}"
[ -n "$docker_n" ] && echo "nas_docker_containers_running{${LABELS}} ${docker_n}"
