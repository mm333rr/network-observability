# The Capes — Infrastructure Connection Map
**Generated:** 2026-02-18 | **Host:** mMacPro (192.168.1.30) | **Location:** Ventura, CA

---

## Network Overview

### MacPro Interfaces
| Interface | IP | Network | Purpose |
|---|---|---|---|
| en0 | 192.168.1.30 | Main LAN (192.168.1.0/24) | Primary LAN, Plex, Docker, clients |
| en1 | 192.168.168.108 | Storage VLAN (192.168.168.0/24, MTU 8000) | NFS to TrueNAS only |
| en2 | 192.168.1.103 | Main LAN | secondary / bonding |

### Nodes
| Node | IP(s) | Role |
|---|---|---|
| Orbi RBR750 | 192.168.1.1 | Gateway, WiFi mesh, WAN |
| mMacPro | 192.168.1.30 / 192.168.168.108 | Plex server, Docker stack |
| TrueNAS | 192.168.168.109 | ZFS NAS — 14 NFS shares |
| mbuntu | 192.168.1.35 | Ubuntu server — Docker, WireGuard VPN |

---

## Docker Observability Stack (172.20.0.0/24)

All containers on bridge network `networkobservability_observability`:

| Container | Bridge IP | Host Port | Role |
|---|---|---|---|
| prometheus | 172.20.0.7 | :9090 | Metrics DB, 90d retention |
| grafana | 172.20.0.8 | :3000 | Dashboard UI |
| loki | 172.20.0.3 | :3100 | Log aggregation backend |
| promtail | 172.20.0.6 | :9080, :1514/udp | Log shipper + syslog receiver |
| telegraf | 172.20.0.2 | :9273 | Custom metrics + exec scripts |
| node-exporter | 172.20.0.5 | :9100 | Host OS metrics |
| cadvisor | 172.20.0.9 | :8080 | Docker container metrics |
| alertmanager | 172.20.0.4 | :9093 | Alert routing → email |

Config root: `/Volumes/4tb-R1/Docker Services/NetworkObservability/`
GitHub: https://github.com/mm333rr/network-observability

---

## NFS Mounts (MacPro ← TrueNAS via 192.168.168.x)

| ZFS Share | Mount Point | Size | Used |
|---|---|---|---|
| /tank/tv | /Volumes/tv | 20 TiB | 43% |
| /tank/movies | /Volumes/movies | 19 TiB | 39% |
| /tank/holding | /Volumes/holding | 12 TiB | 8% |
| /tank/qb | /Volumes/qb | 12 TiB | 2% |
| /tank/images.lossless | /Volumes/images.lossless | 12 TiB | 3% |
| /tank/music.lossless | /Volumes/music.lossless | 12 TiB | 1% |
| /tank/music.compressed | /Volumes/music.compressed | 12 TiB | 1% |
| /tank/music | /Volumes/music | 12 TiB | <1% |
| /tank/comics | /Volumes/comics | 12 TiB | <1% |
| /tank/ebooks | /Volumes/ebooks | 12 TiB | <1% |
| /tank/audiobooks | /Volumes/audiobooks | 12 TiB | <1% |
| /tank/docs | /Volumes/docs | 12 TiB | <1% |
| /tank/images.compressed | /Volumes/images.compressed | 12 TiB | <1% |
| /tank/holding-docs | /Volumes/holding-docs | 12 TiB | <1% |

---

## All Connections

| From | Direction | To | Protocol | Port | Description |
|---|---|---|---|---|---|
| MacPro en1 (168.108) | → | TrueNAS (168.109) | NFS | 2049 | 14 NFS mounts, storage VLAN, MTU 8000 |
| MacPro (.30) | ⇌ | mbuntu (.35) | SSH | 22 | Admin shell |
| MacPro (.30) | ← | mbuntu (.35) | NFS | 2049 | mbuntu NFS exports → MacPro |
| LAN clients | → | Plex (:32400) | HTTPS | 32400 | Media streaming |
| Plex | → | TrueNAS /tank/tv,movies | NFS | 2049 | Media file reads |
| prometheus | → | node-exporter (:9100) | HTTP | 9100 | Host OS metrics |
| prometheus | → | telegraf (:9273) | HTTP | 9273 | Custom metrics (Plex, Orbi, SMART, SMB, security) |
| prometheus | → | cadvisor (:8080) | HTTP | 8080 | Container metrics |
| prometheus | → | loki (:3100/metrics) | HTTP | 3100 | Loki internal metrics |
| prometheus | → | promtail (:9080) | HTTP | 9080 | Promtail health |
| prometheus | → | alertmanager (:9093) | HTTP | 9093 | Alert FIRE/RESOLVE |
| promtail | → | loki (:3100) | HTTP | 3100 | Log push: all streams |
| macOS /var/log/** | → | promtail (bind mount) | file | — | System logs |
| Plex logs | → | promtail (bind mount) | file | — | 4 Plex jobs (main/scanner/transcoder/plugins) |
| Docker socket | → | promtail (docker_sd) | unix | — | Container log autodiscovery |
| Orbi/network gear | → | promtail (:1514) | UDP syslog | 1514 | Network device syslog |
| LaunchAgent disk-metrics | → | telegraf (file input) | file | — | disk_metrics.prom every 30s |
| LaunchAgent net-metrics | → | telegraf (file input) | file | — | net_metrics.prom every 30s |
| telegraf/plex_metrics.sh | → | Plex (host.docker.internal:32400) | HTTP | 32400 | Plex sessions, streams, libraries |
| telegraf/orbi_metrics.sh | → | Orbi (192.168.1.1) | HTTPS SOAP | 443 | Router CPU/RAM/WiFi/per-device |
| telegraf/smart_metrics.sh | → | MacPro disks (host) | exec | — | SMART health + temp, 13 drives, every 5m |
| telegraf/security_metrics.sh | → | /var/log/auth (host) | exec | — | SSH failures, sudo, logins |
| telegraf/smb_metrics.sh | → | smbutil (host) | exec | — | SMB sessions + auth failures |
| alertmanager | → | smtp.gmail.com:587 | SMTP/TLS | 587 | Email alerts → matt@am180.us |
| grafana (:3000) | → | prometheus (:9090) | HTTP | 9090 | PromQL metric queries |
| grafana | → | loki (:3100) | HTTP | 3100 | LogQL log queries |
| Browser/LAN | → | grafana (:3000) | HTTP | 3000 | Dashboard UI |
| cadvisor | → | Docker daemon | unix | — | Container runtime stats |
| mbuntu (.35) | → | WireGuard peers | WireGuard/UDP | 51820 | VPN: Canada-ON, Frankfurt, Rome |

---

## Alert Pipeline

```
prometheus → alerts.yml rules → alertmanager → matt@am180.us (smtp.gmail.com:587)

Warning alerts: repeat every 4h
Critical alerts: repeat every 1h
Inhibit: critical silences duplicate warning for same alertname+instance
```

### Alert Rules
- DiskSpaceLow — boot vol <15% free
- DataVolumeCritical — any /Volumes/* <10% free
- HighCPU — >90% for 10m
- HighMemoryUsage — >90% for 5m
- VolumeAlmostFull — disk_usage_percent >90% (telegraf)
- VolumeCriticallyFull — disk_usage_percent >95% (telegraf)
- SMARTFailure — smart_health == 0
- DriveTemperatureHigh — >65°C for 10m
- DriveTemperatureCritical — >70°C for 5m
- SSHLoginFailures — >5 failures in 5m
- PlexDown — plex_up == 0 for 3m
- InstanceDown — any scrape target down for 2m
- NetworkErrors — TX errors >10/s for 5m

---

## Known Gaps

| Item | Status | Action |
|---|---|---|
| 4tb-R1 at 87% | ⚠️ Warning | Will alert at 90% — audit/clean soon |
| Docker virtual disk 92% | ⚠️ Warning | Run `docker system prune` |
| NAS SSH (no key auth) | ⚠️ Gap | ZFS/SMART on NAS not monitored |
| mbuntu node_exporter | ⚠️ Gap | Commented out in prometheus.yml |
| Grafana 10.3.3 / Loki 2.9.4 | 🔵 Info | Upgrade candidates |
| NFS /Volumes/qb duplicate | 🔵 Info | macOS automounter artifact, harmless |

---

## GitHub Repos (mm333rr)

| Repo | Contents |
|---|---|
| network-observability | Full Docker observability stack |
| plex-batch-optimizer | Batch transcode/remux pipeline |
| plex-optimizer | Subtitle fixer + video optimizer |
| plex-collections | Genre/tag/collection CLI |
| macpro-plex-audit | Server audit report |
| plex-migration-log | Plex SSD→4tb-R1 migration log |
| mbuntu-nfs-docs | NFS automount config |
| mbuntu-server-docs | Full mbuntu server doc set |
