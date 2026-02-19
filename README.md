# NetworkObservability Stack — The Capes Homelab

Hybrid observability stack for the Mac Pro at 192.168.1.30, The Capes, Ventura CA.
Monitors host system metrics, Docker services, Plex, SMB, Orbi mesh network, and all LAN devices.

**Current version: 2.0.0**

**Stack:** Prometheus · Grafana · Loki · Promtail · Telegraf · Alertmanager · Node Exporter · cAdvisor

---

## Architecture

```
Orbi RBR750 Router (192.168.1.1)
  │  SOAP API ←── telegraf (exec: orbi_metrics.sh every 30s)
  │               per-device RSSI, linkspeed, mesh node, WAN, CPU/RAM
  │
MacPro Host (192.168.1.30 · 8-core Xeon E5 · 64GB RAM · macOS 12)
  │  /var/log/**   ←── Promtail
  │  Docker logs   ←── Promtail (docker_sd_configs)
  │  host stats    ←── Node Exporter :9100
  │  custom metrics ←── Telegraf :9273
  │      cpu, mem, disk, processes, SMART, Plex, SMB, security events
  │
  ├── Prometheus   :9090  ← scrapes Node Exporter, Telegraf, Alertmanager
  ├── Loki         :3100  ← receives logs from Promtail
  ├── Alertmanager :9093  ← receives alert rules from Prometheus
  ├── Grafana      :3000  ← queries Prometheus + Loki
  └── cAdvisor     :8080  ← Docker container metrics
```

---

## Quick Start

### Prerequisites
- Docker Desktop 4.28.0 (last version supporting macOS 12 Monterey)
  - DMG at `/Volumes/4tb-R1/Docker Services/Docker-4.28.0-macOS12.dmg`
  - Docker Desktop 4.29+ requires macOS 14 Sonoma

### 1. Configure credentials
```bash
# Set router password for Orbi SOAP scraper
export ROUTER_PASS="your_orbi_admin_password"
# Or store in macOS Keychain:
security add-generic-password -a orbi -s orbi_router -w "your_password"
```

Edit `alertmanager/alertmanager.yml` with your email credentials:
```yaml
smtp_from: 'alerts@yourdomain.com'
smtp_auth_username: 'your@gmail.com'
smtp_auth_password: 'your_gmail_app_password'
```

### 2. Start the stack
```bash
cd "/Volumes/4tb-R1/Docker Services/NetworkObservability"
./manage.sh start
```

### 3. Access Grafana
Open http://localhost:3000 (admin / admin — change on first login)

---

## Management Commands

| Command | Description |
|---|---|
| `./manage.sh start` | Start all services |
| `./manage.sh stop` | Stop all services (data preserved) |
| `./manage.sh restart` | Restart all services |
| `./manage.sh status` | Show container status |
| `./manage.sh logs <service>` | Tail logs for specific service |
| `./manage.sh pull` | Pull updated images |
| `./manage.sh clean` | Remove everything including volumes ⚠️ |

---

## Service URLs

| Service | URL | Notes |
|---|---|---|
| Grafana | http://localhost:3000 | Main dashboard UI |
| Prometheus | http://localhost:9090 | Metrics browser + PromQL |
| Alertmanager | http://localhost:9093 | Alert routing UI |
| Loki | http://localhost:3100 | Log backend (use via Grafana) |
| Promtail | http://localhost:9080 | Log shipper status |
| Telegraf | http://localhost:9273/metrics | Raw Prometheus metrics |
| Node Exporter | http://localhost:9100/metrics | Host stats |
| cAdvisor | http://localhost:8080 | Container metrics |

---

## Grafana Dashboards

All dashboards live in `grafana/dashboards/` and are version-controlled.

| File | UID | Title | Description |
|---|---|---|---|
| `home.json` | `capes-home` | Capes Homelab — Overview | Homepage with links to all dashboards |
| `telegraf-macpro-system.json` | `telegraf-macpro-system` | 📊 Telegraf System — Mac Pro | CPU, RAM, disk, SMART, Plex, SMB, security |
| `capes-network-orbi.json` | `capes-network-snmp` | 🌐 Network — Orbi Mesh & Capes LAN | Router health, per-device RSSI/speed, latency |
| `node-exporter-full.json` | `rYdddlPWk` | Node Exporter Full | Detailed host metrics (community dashboard) |
| `loki-logs.json` | `sadlil-loki-apps-dashboard` | 📋 Log Browser | Loki log explorer |

---

## Orbi SOAP Scraper (`scripts/orbi_metrics.sh`)

The Netgear RBR750 does not support SNMP. We use the SOAP API instead.

- **Endpoint:** `https://192.168.1.1/soap/server_sa/`
- **Auth:** HTTP Basic (admin / `$ROUTER_PASS`)
- **Interval:** 30 seconds
- **Dependency:** pure awk/sed/grep — no Python, works in Alpine containers

### Metrics produced

| Metric | Labels | Description |
|---|---|---|
| `orbi_up` | — | Router reachable (1/0) |
| `orbi_wan_up` | `wan_ip` | WAN connected (1/0) |
| `orbi_cpu_utilization_pct` | — | Router CPU % |
| `orbi_memory_utilization_pct` | — | Router RAM % |
| `orbi_radio_up` | — | WiFi radio status |
| `orbi_radio_info` | `ssid`, `channel`, `security` | WiFi info gauge |
| `orbi_firmware_info` | `firmware`, `model`, `serial` | Firmware info gauge |
| `orbi_devices_total` | — | Total connected devices |
| `orbi_devices_by_connection` | `conn_type` | Count by 2.4GHz/5GHz/wired |
| `orbi_node_device_count` | `node` | Count per mesh node |
| `orbi_device_rssi` | `name`,`ip`,`mac`,`band`,`node`,`type`,`brand` | Per-device signal |
| `orbi_device_linkspeed_mbps` | `name`,`ip`,`band` | Per-device link speed |
| `orbi_satellite_up` | `satellite_mac` | Satellite node reachable |
| `orbi_ping_rtt_ms` | `target`,`target_ip` | Ping RTT to router/Cloudflare/Google |
| `orbi_dns_resolve_ms` | — | DNS resolution latency |

---

## Telegraf Host Metrics

Telegraf runs in Docker, scraping the Mac Pro host via mounted paths and exec scripts.

**Inputs configured:**
- `cpu` — per-core and aggregate CPU usage
- `mem` — RAM used/free/cached/available
- `disk` — usage % and bytes per volume (/, /Volumes/4tb-R1, /Volumes/6tb-R1, /Volumes/500g-R1)
- `processes` — running/sleeping/zombie process counts
- `[[inputs.exec]] orbi_metrics.sh` — Orbi SOAP metrics (see above)
- Custom exec scripts: Plex, SMB, SMART, security events

---

## Data Persistence

All data lives in `./data/` (bind-mounted, on 4tb-R1):

| Path | Contents | Retention |
|---|---|---|
| `./data/prometheus/` | Metrics time series | 90 days |
| `./data/grafana/` | Dashboards, users, settings | Indefinite |
| `./data/loki/` | Log data | 90 days |
| `./data/alertmanager/` | Silence records | Indefinite |

---

## Monitoring the .35 Server

To also monitor `192.168.1.35` (Doris):
1. Install Node Exporter on it (see `grafana/dashboards/` for Doris Overview dashboard)
2. Uncomment the `node-exporter-server35` job in `prometheus/prometheus.yml`
3. `./manage.sh restart`

---

## Migrating to Raspberry Pi

All images have ARM64 builds. To migrate:
1. Copy this entire `NetworkObservability/` folder to the Pi
2. Copy `./data/` to preserve historical data
3. `curl -sSL https://get.docker.com | sh` on the Pi
4. `./manage.sh start`

No config changes needed — everything uses container-internal networking.

---

## Directory Structure

```
NetworkObservability/
├── docker-compose.yml
├── manage.sh
├── README.md
├── CHANGELOG.md
├── prometheus/
│   ├── prometheus.yml          # Scrape targets + retention config
│   └── alerts.yml              # Alert rules (disk, CPU, mem, down)
├── loki/
│   └── loki-config.yml
├── promtail/
│   └── promtail-config.yml     # Log sources: /var/log, Docker SD, syslog UDP
├── telegraf/
│   └── telegraf.conf           # Host metrics + Orbi SOAP exec input
├── alertmanager/
│   └── alertmanager.yml        # Alert routing + email (matt@am180.us)
├── scripts/
│   └── orbi_metrics.sh         # Orbi RBR750 SOAP API scraper v2.0.0
├── host-metrics/
│   └── disk_metrics.prom       # Static disk metrics (updated by cron)
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/        # Auto-configured Prometheus + Loki
│   │   └── dashboards/         # Dashboard provisioning config
│   └── dashboards/             # JSON dashboard exports (version-controlled)
└── data/                       # Persistent bind-mount data (not in git)
    ├── prometheus/
    ├── grafana/
    ├── loki/
    └── alertmanager/
```

---

## Pinned Versions

| Component | Version |
|---|---|
| Grafana | 10.3.3 |
| Prometheus | 2.50.1 |
| Node Exporter | 1.7.0 |
| Loki | 2.9.4 |
| Promtail | 2.9.4 |
| Telegraf | 1.29-alpine |
| Alertmanager | 0.26.0 |
| cAdvisor | 0.49.1 |
| Docker Desktop | 4.28.0 (macOS 12 Monterey max) |
