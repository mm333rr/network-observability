# NetworkObservability Stack

Hybrid observability stack for The Capes homelab — MacPro host, migratable to Raspberry Pi.

**Stack:** Prometheus + Node Exporter + Telegraf (SNMP) + Loki + Promtail + Grafana + Alertmanager

**Location:** `/Volumes/4tb-R1/Docker Services/NetworkObservability/`

---

## Architecture

```
Network Devices (router/switch/AP)
  │  syslog UDP → Promtail :1514
  │  SNMP poll  ← Telegraf
  │
MacPro Host
  │  /var/log/*  ← Promtail
  │  host stats  ← Node Exporter :9100
  │
  ├── Prometheus :9090  ← scrapes Node Exporter, Telegraf :9273, Alertmanager
  ├── Loki       :3100  ← receives from Promtail
  ├── Alertmanager :9093 ← receives rules from Prometheus
  └── Grafana    :3000  ← queries Prometheus + Loki → unified dashboards + alerts
```

---

## Quick Start

### 1. Install Docker Desktop 4.28.0
Docker Desktop 4.28.0 is the last version supporting macOS 12 Monterey.
The DMG was downloaded to: `/Volumes/4tb-R1/Docker Services/Docker-4.28.0-macOS12.dmg`

Install it, open Docker Desktop, and wait for the whale icon to show in the menu bar.

### 2. Configure Alertmanager
Edit `alertmanager/alertmanager.yml` with your email credentials:
```yaml
smtp_from: 'alerts@yourdomain.com'
smtp_auth_username: 'your@gmail.com'
smtp_auth_password: 'your_gmail_app_password'
```

### 3. Configure SNMP on your router
In `telegraf/telegraf.conf`, update the router IP:
```
agents = ["udp://192.168.1.1:161"]  # Replace with your router's IP
community = "public"                  # Replace with your SNMP community string
```
Enable SNMP on your router (usually under Administration → SNMP).

### 4. Configure syslog on network devices
Point your router/switch syslog to: `<MacPro-IP>:1514` (UDP)

### 5. Start the stack
```bash
cd "/Volumes/4tb-R1/Docker Services/NetworkObservability"
./manage.sh start
```

### 6. Access Grafana
Open http://localhost:3000
Login: admin / changeme_on_first_login
**Change your password immediately!**

---

## Management Commands

| Command | Description |
|---|---|
| `./manage.sh start` | Start all services |
| `./manage.sh stop` | Stop all services (data preserved) |
| `./manage.sh restart` | Restart all services |
| `./manage.sh status` | Show container status |
| `./manage.sh logs grafana` | Tail logs for specific service |
| `./manage.sh pull` | Pull updated images |
| `./manage.sh clean` | Remove everything including volumes ⚠️ |

---

## Service URLs

| Service | URL | Notes |
|---|---|---|
| Grafana | http://localhost:3000 | Main dashboard UI |
| Prometheus | http://localhost:9090 | Metrics browser + query |
| Alertmanager | http://localhost:9093 | Alert routing UI |
| Loki | http://localhost:3100 | Log backend (use via Grafana) |
| Promtail | http://localhost:9080 | Log shipper status |
| Telegraf | http://localhost:9273/metrics | Raw Prometheus metrics |
| Node Exporter | http://localhost:9100/metrics | Host stats |

---

## Data Persistence

All data lives in `./data/`:
- `./data/prometheus/` — metrics time series (90 day retention)
- `./data/grafana/` — dashboards, users, settings
- `./data/loki/` — log data (90 day retention)
- `./data/alertmanager/` — silence records

---

## Adding Server 192.168.1.35

To also monitor the `.35` server:
1. SSH into it and install Node Exporter:
   ```bash
   # On 192.168.1.35 (Linux)
   docker run -d --pid=host --net=host \
     -v /proc:/host/proc:ro -v /sys:/host/sys:ro -v /:/rootfs:ro \
     --name node-exporter prom/node-exporter:latest
   ```
2. Uncomment the `node-exporter-server35` job in `prometheus/prometheus.yml`
3. Run `./manage.sh restart`

---

## Migrating to Raspberry Pi

All images used have ARM64 builds. To migrate:
1. Copy this entire `NetworkObservability/` folder to the Pi
2. Copy `./data/` directory to preserve historical data
3. Install Docker on the Pi: `curl -sSL https://get.docker.com | sh`
4. `./manage.sh start`

No configuration changes needed — everything uses container-internal networking.

---

## Recommended Grafana Dashboards to Import

After startup, import these from grafana.com (Dashboard → Import → Enter ID):

| ID | Name |
|---|---|
| 1860 | Node Exporter Full |
| 13639 | Logs / Loki |
| 7587 | Telegraf: system dashboard |
| 9734 | SNMP Stats |

---

## Directory Structure

```
NetworkObservability/
├── docker-compose.yml
├── manage.sh
├── README.md
├── CHANGELOG.md
├── prometheus/
│   ├── prometheus.yml      # Scrape targets
│   └── alerts.yml          # Alert rules
├── loki/
│   └── loki-config.yml
├── promtail/
│   └── promtail-config.yml # Log sources + syslog receiver
├── telegraf/
│   └── telegraf.conf       # SNMP + host metrics
├── alertmanager/
│   └── alertmanager.yml    # Alert routing + email
├── grafana/
│   ├── provisioning/
│   │   ├── datasources/    # Auto-configured Prometheus + Loki
│   │   └── dashboards/
│   └── dashboards/         # JSON dashboard files go here
└── data/                   # All persistent data (bind mounts)
    ├── prometheus/
    ├── grafana/
    ├── loki/
    └── alertmanager/
```

---

## Versions Pinned

| Component | Version |
|---|---|
| Grafana | 10.3.3 |
| Prometheus | 2.50.1 |
| Node Exporter | 1.7.0 |
| Loki | 2.9.4 |
| Promtail | 2.9.4 |
| Telegraf | 1.29-alpine |
| Alertmanager | 0.26.0 |
| Docker Desktop | 4.28.0 (macOS 12 Monterey compatible) |
