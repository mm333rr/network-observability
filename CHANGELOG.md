# CHANGELOG — NetworkObservability Stack

## [1.1.0] — 2026-02-18

### Added
- **Promtail: Docker container log discovery** — added `docker_sd_configs` job using mounted Docker socket; auto-discovers all running containers and labels logs with `container`, `service`, `job=docker`, `host=macpro`
- **Promtail: Docker socket mount** — added `/var/run/docker.sock` bind to `docker-compose.yml` for Promtail container log scraping
- **Promtail: Plex log severity pipeline** — regex pipeline stage extracts `level` label (DEBUG/INFO/WARN/ERROR) from Plex log format
- **Promtail: Recursive macOS log glob** — changed `/var/log/*.log` to `/var/log/**/*.log` to capture subdirectories (launchd, displaypolicy, etc.)
- **Promtail: Section headers** — added descriptive comment blocks to all scrape_config jobs for readability
- **host-metrics**: Updated `disk_metrics.prom` with current disk usage data
- **Grafana dashboards**: Iterative updates to home.json, loki-logs.json, snmp-stats.json, telegraf-system.json
- **grafana/dashboards/test-35.json**: Added experimental dashboard for 192.168.1.35 server monitoring

### Changed
- docker-compose.yml: Promtail now mounts `/var/run/docker.sock` to support Docker SD config

### Notes
- All 8 containers running healthy as of 2026-02-18 18:xx
- Stack version bumped 1.0.0 → 1.1.0

---

## [1.0.0] — 2026-02-18

### Added
- Initial stack: Prometheus 2.50.1, Grafana 10.3.3, Loki 2.9.4, Promtail 2.9.4, Alertmanager 0.26.0, Node Exporter 1.7.0, Telegraf 1.29
- All config files with sensible defaults for Capes homelab
- Prometheus scrape targets: Node Exporter, Telegraf, Alertmanager, self
- Loki with 90-day log retention and TSDB schema
- Promtail: macOS /var/log tailing + UDP syslog receiver on port 1514
- Telegraf: SNMP polling config (router at 192.168.1.1), host metrics, Prometheus exposition
- Alertmanager: email routing, critical/warning severity routing, inhibition rules
- Alert rules: disk space, CPU, memory, instance down, network errors
- Grafana provisioning: auto-datasources for Prometheus + Loki
- manage.sh: start/stop/restart/status/logs/pull/clean commands
- Data directories bound to ./data/ on 4tb-R1 volume for persistence
- README with quick-start, Pi migration guide, dashboard import IDs
- Docker Desktop 4.28.0 DMG downloaded (last version supporting macOS 12 Monterey)

### Notes
- macOS 12.7.6 Monterey on Intel Xeon Mac Pro
- Boot volume: 166GB free / 234GB ✅
- 4TB-R1 volume: 519GB free / 3.6TB ✅ (stack lives here)
- Docker Desktop 4.29+ requires macOS 14 Sonoma — locked to 4.28.0 until macOS upgrade
