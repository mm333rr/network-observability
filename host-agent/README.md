# host-agent/

This directory contains the **host-side metric writers** — scripts that run natively on the host OS (not in Docker) and write Prometheus `.prom` files that Telegraf reads via `[[inputs.file]]`.

This two-step approach is necessary because Docker containers cannot directly access macOS APFS volumes, macOS network interfaces, or host-level disk devices.

---

## Why this exists

Telegraf runs inside a container. On macOS, Docker Desktop runs containers in a Linux VM — so `df`, `ip`, and `/proc/net/dev` inside the container see the VM's filesystem and network, not the Mac's real volumes or `en0`/`en1`. The solution: run the metric scripts natively on the host, write the results to `.prom` files in `host-metrics/`, and have Telegraf read those files.

---

## macOS (Mac Pro) — LaunchAgents

The macOS scripts live in `../host-metrics/` and are driven by LaunchAgents in `~/Library/LaunchAgents/`:

| LaunchAgent plist | Script | Interval |
|---|---|---|
| `com.capes.disk-metrics.plist` | `write_disk_metrics.sh` | 30s |
| `com.capes.net-metrics.plist` | `write_net_metrics.sh` | 30s |

SMART metrics are run by Telegraf exec directly (not a LaunchAgent).

**Load commands (run once):**
```bash
cp ../host-metrics/com.capes.disk-metrics.plist ~/Library/LaunchAgents/
cp ../host-metrics/com.capes.net-metrics.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.capes.disk-metrics.plist
launchctl load ~/Library/LaunchAgents/com.capes.net-metrics.plist
```

---

## Linux (Raspberry Pi / Ubuntu) — cron

The Linux equivalents live here in `host-agent/`. They are installed by `pi-setup.sh` as cron jobs for the current user.

| Script | Interval | Output |
|---|---|---|
| `write_disk_metrics_linux.sh` | every 1 min | `../host-metrics/disk_metrics.prom` |
| `write_net_metrics_linux.sh` | every 1 min | `../host-metrics/net_metrics.prom` |
| `write_smart_metrics_linux.sh` | every 5 min | `../host-metrics/smart_metrics.prom` |

**Manual cron install:**
```bash
(crontab -l 2>/dev/null; \
 echo "*/1 * * * * bash $(pwd)/write_disk_metrics_linux.sh"; \
 echo "*/1 * * * * bash $(pwd)/write_net_metrics_linux.sh"; \
 echo "*/5 * * * * bash $(pwd)/write_smart_metrics_linux.sh") | crontab -
```

**Or just run `pi-setup.sh`** from the stack root — it handles this automatically.

---

## Migrating between platforms

When moving the stack from Mac Pro to Pi:
1. Run `pi-setup.sh` on the Pi — installs cron jobs automatically
2. Update `HOST_HOSTNAME` in `.env` (e.g. `macpro` → `pi`)
3. The `.prom` files in `../host-metrics/` will be overwritten by the new cron jobs within 1–5 minutes of first run
4. The old macOS LaunchAgents on the Mac Pro can be unloaded once the stack is confirmed running on Pi
