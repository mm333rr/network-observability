# CHANGELOG — network-observability

All notable changes to the Capes observability stack.

---

## [2.0.0] - 2026-03-23

### Added
- **AdGuard Home DNS monitoring** — full end-to-end observability for DNS:
  - `adguard-exporter` container (`ghcr.io/henrywhitaker3/adguard-exporter:latest`)
    port `192.168.1.5:9618`, polls `http://192.168.1.2:3000` every 15s
  - Prometheus scrape job `adguard-exporter` (15s interval)
  - `ADGUARD_PASS` added to `/srv/docker/observability/.env` for boot-time auth
  - Grafana dashboard `adguard-dns.json` (uid: `adguard-dns-capes`):
    - Health row: AdGuard running/protection/query-rate/block-rate/latency/client-count stat panels
    - Time-series: DNS query rate vs block rate, avg latency, upstream resolver breakdown
    - Tables: top 15 querying clients, top 15 blocked domains
    - 7-day totals: query count, blocked count, block rate, safebrowsing blocks
  - 7 Prometheus alert rules (group `adguard_dns`):
    - `AdGuardDown` (critical) — exporter unreachable for 2m
    - `AdGuardProtectionDisabled` (critical) — filtering disabled for 1m
    - `AdGuardNotRunning` (critical) — AGH process stopped for 2m
    - `DNSQueryRateDrop` (warning) — <1 query/min for 5m (detects DNS unreachable)
    - `DNSBlockRateSurge` (warning) — >60% block rate for 10m (detects over-blocking)
    - `DNSHighLatency` (warning) — >100ms avg for 5m
    - `DNSCriticalLatency` (critical) — >500ms avg for 3m

### Context
Added after extended AdGuard/YouTube debugging session (2026-03-23). Root causes
discovered during that session that this monitoring would have caught immediately:
- `DNSQueryRateDrop` would have fired when Apple TV stopped receiving DNS answers
  due to rate limiting (was 20 req/s for entire /24 subnet — now 300/s)
- `DNSBlockRateSurge` would have flagged the Perflyst Smart-TV list blocking
  `androidtvchannels-pa.googleapis.com` and `androidtvwatsonfe-pa.googleapis.com`
  (caused "account not supported on YouTube TV app" error on Apple TV)
- `AdGuardDown` would catch any future AdGuard restart failures

---

## [1.3.0] - 2026-03-06

### Added
- Mac Pro node-exporter scrape target (192.168.1.30:9100)
- plex-health-monitor scrape target (192.168.1.30:9101)

## [1.2.0] - 2026-02-22

### Fixed
- Resolved 6 false-positive alerts (OrbiCPU firmware bug, WANIPConnection 401,
  satellite detection, cAdvisor cgroupv2 per-container metrics)
- Raised MacPro CPU threshold 90%->95%, extended window 10m->20m

### Added
- MacPro load average alerts (MacProHighLoad, MacProCriticalLoad)
- MacPro swap/memory pressure alerts (MacProSwapSurging, MacProMemoryPressure)
- Ping-based internet check replacing broken WANIPConnection SOAP

## [1.1.0] - 2026-02-22

### Added
- Initial alert rules: disk, CPU, memory, SSH brute-force, Plex, ZFS, NFS, Docker,
  NAS SMART, Orbi router/mesh, network errors

## [1.0.0] - 2026-02-18

### Added
- Initial stack: Prometheus, Grafana, Loki, Promtail, Alertmanager, Telegraf, cAdvisor

---

## [2.1.0] - 2026-04-01

### Fixed
- **Alertmanager silent SMTP failure (v0.26.0 → v0.27.0)**
  - Root cause: CA certificate bundle in prom/alertmanager:v0.26.0 (dated Aug 2023)
    caused Go TLS client to hang indefinitely on smtp2go STARTTLS handshake.
    Notifications silently dropped — no error logged, no retry, nflog never written.
  - Symptom: FIRING emails sent (from pre-March-26 container state); RESOLVED emails
    never delivered. Zero notify.go log lines after March 26 restart.
  - Fix: upgraded to prom/alertmanager:v0.27.0 (Go 1.21.7 + updated CA roots).
    Full round-trip verified: firing + resolved both delivered in same session.
  - Added --log.level=debug permanently to entrypoint.sh.
  - Commit: b565e1d

### Fixed
- **AdGuard duplicate DHCP lease → adguard-exporter HTTP 500**
  - IP 192.168.1.64 (MAC 5c:ad:ba:4b:90:a0) duplicated in AdGuard lease table.
  - adguard-exporter emitted duplicate Prometheus labels → 500 on every scrape.
  - AdGuardDown + InstanceDown fired ~22:30 UTC March 31 for ~6 hours.
  - Fix: removed duplicate via POST /control/dhcp/remove_static_lease.
  - AdGuard Home DNS/DHCP remained operational throughout.
  - All 10 Prometheus targets confirmed UP post-fix.
