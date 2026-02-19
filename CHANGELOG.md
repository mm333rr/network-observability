# CHANGELOG — NetworkObservability Stack

## [2.0.0] — 2026-02-18

### Added
- **Orbi SOAP API scraper** (`scripts/orbi_metrics.sh`) — replaces SNMP entirely
  - Netgear RBR750 does not expose SNMP; switched to SOAP endpoint at `/soap/server_sa/`
  - HTTP Basic Auth (stateless, no session); credentials via `ROUTER_PASS` env or macOS Keychain
  - 17 metrics: `orbi_up`, `orbi_wan_up`, `orbi_cpu_utilization_pct`, `orbi_memory_utilization_pct`,
    `orbi_radio_up`, `orbi_radio_info`, `orbi_firmware_info`, `orbi_devices_total`,
    `orbi_devices_by_connection`, `orbi_node_device_count`, `orbi_device_rssi`,
    `orbi_device_linkspeed_mbps`, `orbi_satellite_up`, `orbi_ping_rtt_ms`, `orbi_dns_resolve_ms`
  - Per-device labels: `name`, `ip`, `mac`, `band`, `node`, `type`, `brand`
  - Satellite vs router detection via `ConnAPMAC` field comparison
  - Zero Python dependency — pure awk/sed/grep, runs in Alpine/Debian containers
- **Grafana: Telegraf System dashboard** (`grafana/dashboards/telegraf-macpro-system.json`)
  - 19 panels: CPU/RAM stats + timeseries, disk usage bargauge + table, drive temps (13 disks),
    SMART health, security events, Plex stream tracking, SMB sessions
  - UID: `telegraf-macpro-system`
- **Grafana: Network/Orbi dashboard** (`grafana/dashboards/capes-network-orbi.json`)
  - 22 panels: router/WAN/satellite health, latency timeseries (RTT + DNS),
    per-device RSSI bargauge, link speed bargauge, connection type + node pie charts,
    router CPU/RAM history, firmware + radio info table
  - UID: `capes-network-snmp` (preserves homepage link)

### Changed
- `telegraf/telegraf.conf`: replaced `[[inputs.snmp]]` block with `[[inputs.exec]]` calling orbi_metrics.sh
- `telegraf/telegraf.conf`: corrected script path to container-relative `/scripts/orbi_metrics.sh`
- `docker-compose.yml`: added `ROUTER_PASS` env var to Telegraf service

### Removed
- `grafana/dashboards/snmp-stats.json` — broken stub referencing dead SNMP queries
- `grafana/dashboards/telegraf-system.json` — broken stub with no real metric queries
- `grafana/dashboards/test-35.json` — dev test dashboard

### Notes
- All 17 LAN devices reporting RSSI + linkspeed + mesh node assignment
- Satellite node (10:0c:6b:f1:ae:c5) tracking 4 devices; router tracking 13
- SOAP approach is portable to any Netgear Orbi running firmware V7.x

---

## [1.1.0] — 2026-02-18

### Added
- **Promtail: Docker container log discovery** — `docker_sd_configs` job using mounted Docker socket;
  auto-discovers all running containers, labels logs with `container`, `service`, `job=docker`, `host=macpro`
- **Promtail: Docker socket mount** — `/var/run/docker.sock` bind in `docker-compose.yml`
- **Promtail: Plex log severity pipeline** — regex stage extracts `level` label (DEBUG/INFO/WARN/ERROR)
- **Promtail: Recursive macOS log glob** — `/var/log/**/*.log` to capture subdirectories
- **host-metrics**: `disk_metrics.prom` with current disk usage data for all 5 volumes
- **Grafana dashboards**: home overview, loki log browser, Node Exporter Full, Blackbox Exporter

### Changed
- `docker-compose.yml`: Promtail mounts `/var/run/docker.sock` for Docker SD config

---

## [1.0.0] — 2026-02-18

### Added
- Initial stack: Prometheus 2.50.1, Grafana 10.3.3, Loki 2.9.4, Promtail 2.9.4,
  Alertmanager 0.26.0, Node Exporter 1.7.0, Telegraf 1.29-alpine
- Prometheus scrape targets: Node Exporter, Telegraf :9273, Alertmanager, self
- Loki with 90-day log retention and TSDB schema
- Promtail: macOS `/var/log` tailing + UDP syslog receiver on port 1514
- Alertmanager: email routing, critical/warning severity, inhibition rules
- Alert rules: disk space, CPU, memory, instance down, network errors
- Grafana provisioning: auto-datasources for Prometheus + Loki
- `manage.sh`: start/stop/restart/status/logs/pull/clean commands
- Data directories bound to `./data/` on 4tb-R1 for persistence
- README with quick-start, Pi migration guide
- Docker Desktop 4.28.0 (last version supporting macOS 12 Monterey)
