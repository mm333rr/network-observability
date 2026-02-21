# CHANGELOG — NetworkObservability Stack

## [3.0.0] — 2026-02-21

### Portable Stack — Pi-Ready Refactor

Goal: stack can be moved to any Linux/ARM host (Raspberry Pi) with zero config file edits —
only `.env` and `~/.secrets/smtp.env` need updating on the new host.

#### `.env` — all host-specific values extracted
- Added `HOST_HOSTNAME` — label embedded in all metrics/logs (was hardcoded `macpro`)
- Added `HOST_LAN_IP` — Grafana server domain + manage.sh URL display
- Added `PLEX_HOST` / `PLEX_PORT` — Plex server IP (decoupled from stack host)
- Added `SMTP_SECRETS_FILE` — absolute path to smtp.env (was hardcoded `/Users/mProAdmin/...`)

#### `docker-compose.yml`
- `alertmanager` `env_file:` now uses `${SMTP_SECRETS_FILE}` — no hardcoded Mac path
- Grafana `GF_SERVER_DOMAIN` now uses `${HOST_LAN_IP:-192.168.1.30}`
- Telegraf env block passes `PLEX_HOST` and `PLEX_PORT` to container

#### `scripts/plex_metrics.sh`
- Replaced `host.docker.internal:32400` with `${PLEX_HOST:-192.168.1.30}:${PLEX_PORT:-32400}`
- `host.docker.internal` is macOS Docker Desktop only — breaks on Pi (Linux Docker)

#### `scripts/smart_metrics.sh`
- Rewrote disk enumeration: detects macOS vs Linux
- macOS: `diskutil list` (APFS, external drives)
- Linux: `lsblk -d` (sd*, nvme* block devices)
- NVMe temperature fallback added

#### `manage.sh`
- Fixed long-standing `COMPPOSE` typo (was causing silent failures on restart/status/logs)
- Fixed `STACK_DIR` assignment (was a literal string, not expanded)
- Reads `HOST_LAN_IP` from `.env` for URL display in `start` output
- DNS check updated from `.am180.us` to `.capes.local`

#### `host-agent/` — new Linux cron equivalents
- `write_disk_metrics_linux.sh` — replaces macOS LaunchAgent for disk usage
- `write_net_metrics_linux.sh` — replaces macOS LaunchAgent for network counters (reads `/proc/net/dev`)
- `write_smart_metrics_linux.sh` — SMART writer for cron (Linux block devices)
- `README.md` — documents both-platform approach and migration steps

#### `pi-setup.sh` — new Pi bootstrap script
- Installs Docker, smartmontools
- Installs cron jobs for all three host-agent metric writers
- Creates `~/.secrets/smtp.env` placeholder
- Sets correct data directory permissions (prometheus=65534, grafana=472)

#### `AdGuardHome` stack — promoted to full DNS + DHCP
- Switched to `network_mode: host` (required for DHCP broadcast)
- DHCP enabled: range 192.168.1.50–200, gateway 192.168.1.1, DNS option 6 → 192.168.1.2
- 15 static DHCP leases: all known Capes devices pinned to their IPs
- DNS rewrites added: `*.capes.local` for all infrastructure + services
  - `macpro.capes.local`, `mbuntu.capes.local`, `pi.capes.local` (reserved)
  - `grafana/prometheus/alertmanager/loki/cadvisor.capes.local` → Mac Pro
  - All *arr services → mbuntu
- Retained all `*.am180.us` external rewrites
- `adguard-exporter` now uses `192.168.1.2:3000` (host networking) instead of container hostname
- Pi reservation noted in config (MAC TBD, IP 192.168.1.5 reserved)

#### `prometheus.yml`
- `adguard` scrape target fixed: `192.168.1.2:9617` (exporter on host network, not in observability bridge)
- `adguard-exporter` container was in AdGuard compose, not this one — previous target `adguard-exporter:9617` was unreachable from this network

## [2.3.0] — 2026-02-21

### Changed — Alertmanager SMTP: Gmail → smtp2go

**Security fix:** removed hardcoded Gmail app password from `alertmanager.yml`

- `alertmanager.yml` — SMTP block now uses token placeholders; no credentials in file or git
- `alertmanager/entrypoint.sh` — new startup script; `sed`-substitutes tokens from env vars at container start; resolved config written to `/tmp/alertmanager-resolved.yml`
- `docker-compose.yml` — alertmanager now loads `env_file: ~/.secrets/smtp.env`; old inline `environment:` SMTP vars and `command:` block removed

**smtp2go config:**
- Host: `mail.smtp2go.com:587` STARTTLS
- Account: `dockeralerts`
- Verified sender: `alertmanager@am180.us`
- Secrets: `~/.secrets/smtp.env` (Mac Pro) · `/srv/docker/secrets/smtp.env` (mbuntu)
- Ref: `mm333rr/mbuntu-server-docs` → `credentials/smtp-reference.md`

**Tested:** live email delivered to `matt@am180.us` ✅

---

## [2.2.0] — 2026-02-19

### Added — Plex enrichment

**Metrics (`scripts/plex_metrics.sh`)**
- Rewrote from scratch in pure bash/awk (no Python/jq — Telegraf image has neither)
- `plex_stream_info` — per-session gauge with labels: `user`, `player`, `device`,
  `platform`, `state`, `media_type`, `video_resolution`, `audio_codec`,
  `video_codec`, `decision` (direct/transcode)
- `plex_stream_bitrate_kbps` — per-session bitrate with same label set
- `plex_library_section` — one gauge per library section with `section`, `type`, `key`
- Both sessions and library fetched in single script invocation; library is best-effort

**Logs (`promtail/promtail-config.yml`)**
- Replaced monolithic `plex` job with four focused jobs:
  - `plex` — main server log with enriched pipeline (drops noisy VERBOSE polling)
  - `plex-scanner` — scanner/analysis logs (drops VERBOSE/DEBUG)
  - `plex-transcoder` — Plex Transcoder Statistics log
  - `plex-plugins` — Plugin Logs subdirectory
- Main plex pipeline extracts labels: `level`, `plex_event`, `method`, `endpoint`,
  `client_ip`, `user`, `client_device`, `client_platform`, `client_product`,
  `http_status`, `response_ms`, `live_count`
- Drop stage silences routine `/status/sessions` polling (Telegraf-generated) to
  reduce log volume by ~80%

**Grafana (`grafana/dashboards/plex.json`)**
- New dashboard UID `capes-plex` — "🎬 Plex Media Server"
- 26 panels across 5 rows:
  - **Status row**: Plex up/down, active streams, direct/transcode counts, error/warn
    5-minute counts from Loki
  - **Stream Activity**: stacked timeseries of stream counts + bitrate timeseries
  - **Client Breakdown**: bargauge by platform / device / user / media type /
    resolution / decision
  - **Libraries**: table of library sections with type/key labels
  - **Logs**: Errors & Warnings · Request log · Scanner/Metadata · Transcoder ·
    All-plex live tail — all as Loki log panels

**Home dashboard (`grafana/dashboards/home.json`)**
- Added Plex row (id 200–205): server up/down, active streams, transcoding count,
  errors-5m, and a navigation link card to the Plex dashboard
- Added Plex dashboard link to the Quick Links table

## [2.1.0] — 2026-02-18

### Fixed
- **Node Exporter: macOS network interfaces not visible** — Docker Desktop runs node-exporter in a
  Linux VM network namespace; `en0`/`en1` were never visible, only `eth0`/`lo`/tunnel adapters.
  - Added `host-metrics/write_net_metrics.sh` — runs natively on macOS, reads `netstat -ib` for
    real interface counters (en0, en1, en2, en3), writes `host-metrics/net_metrics.prom` atomically.
  - Added `host-metrics/com.capes.net-metrics.plist` — LaunchAgent runs the script every 30s.
    Load with: `cp host-metrics/com.capes.net-metrics.plist ~/Library/LaunchAgents/ && launchctl load ~/Library/LaunchAgents/com.capes.net-metrics.plist`
  - Updated `telegraf/telegraf.conf` `[[inputs.file]]` to include `net_metrics.prom` alongside
    `disk_metrics.prom` and `smart_metrics.prom`.
  - Metrics flowing: `net_bytes_recv_total`, `net_bytes_sent_total`, `net_packets_recv/sent_total`,
    `net_errors_recv/sent_total`, `net_drops_recv_total`, `net_link_up` — all with `interface` label.
- **Plex metrics: token placeholder in script** — `plex_metrics.sh` had hardcoded fallback
  `YOUR_PLEX_TOKEN_HERE`; removed fallback so Telegraf exec `environment` block is the sole source.
  The real token was already correctly set in `.env` and passed to the container; Plex metrics were
  actually functioning — confirmed with live API test returning `plex_up=1`, `plex_active_streams=0`.

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
