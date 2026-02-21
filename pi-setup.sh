#!/usr/bin/env bash
# =============================================================================
# pi-setup.sh — First-boot bootstrap for NetworkObservability on Raspberry Pi
# Run once as the pi user after copying the NetworkObservability folder.
#
# What this does:
#   1. Installs Docker + Docker Compose plugin
#   2. Adds current user to docker group
#   3. Installs smartmontools (for smart_metrics.sh)
#   4. Installs cron jobs for disk/net/NAS metrics (replacing macOS LaunchAgents)
#   5. Creates ~/.secrets/smtp.env placeholder
#   6. Sets correct permissions on data/ directories
#
# Usage:
#   scp -r /Volumes/4tb-R1/Docker\ Services/NetworkObservability pi@192.168.1.5:~/
#   ssh pi@192.168.1.5
#   cd ~/NetworkObservability
#   cp .env.example .env   # then edit .env for Pi values
#   bash pi-setup.sh
# =============================================================================
set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[setup]${NC} $*"; }
warn() { echo -e "${YELLOW}[warn]${NC} $*"; }

# ---------------------------------------------------------------------------
# 1. Docker
# ---------------------------------------------------------------------------
if ! command -v docker &>/dev/null; then
    log "Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo usermod -aG docker "$USER"
    log "Docker installed. NOTE: log out and back in for group change to take effect."
else
    log "Docker already installed: $(docker --version)"
fi

# ---------------------------------------------------------------------------
# 2. smartmontools
# ---------------------------------------------------------------------------
if ! command -v smartctl &>/dev/null; then
    log "Installing smartmontools..."
    sudo apt-get update -qq && sudo apt-get install -y smartmontools
else
    log "smartmontools already installed."
fi

# ---------------------------------------------------------------------------
# 3. Data directory permissions
# ---------------------------------------------------------------------------
log "Setting data directory permissions..."
mkdir -p "${STACK_DIR}/data/prometheus" \
         "${STACK_DIR}/data/grafana" \
         "${STACK_DIR}/data/loki" \
         "${STACK_DIR}/data/alertmanager"
chmod -R 755 "${STACK_DIR}/data"
# Prometheus runs as nobody (65534)
sudo chown -R 65534:65534 "${STACK_DIR}/data/prometheus" 2>/dev/null || true
# Grafana runs as 472
sudo chown -R 472:472 "${STACK_DIR}/data/grafana" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 4. Cron jobs for host metrics (replaces macOS LaunchAgents)
#    These write .prom files that Telegraf reads via [[inputs.file]]
# ---------------------------------------------------------------------------
log "Installing host metrics cron jobs..."
CRON_DISK="*/1 * * * * bash ${STACK_DIR}/host-agent/write_disk_metrics_linux.sh > /tmp/cron_disk.log 2>&1"
CRON_NET="*/1 * * * * bash ${STACK_DIR}/host-agent/write_net_metrics_linux.sh > /tmp/cron_net.log 2>&1"
CRON_SMART="*/5 * * * * bash ${STACK_DIR}/host-agent/write_smart_metrics_linux.sh > /tmp/cron_smart.log 2>&1"

(crontab -l 2>/dev/null | grep -v "write_disk_metrics_linux\|write_net_metrics_linux\|write_smart_metrics_linux"; \
 echo "$CRON_DISK"; echo "$CRON_NET"; echo "$CRON_SMART") | crontab -
log "Cron jobs installed."

# ---------------------------------------------------------------------------
# 5. SMTP secrets placeholder
# ---------------------------------------------------------------------------
mkdir -p ~/.secrets && chmod 700 ~/.secrets
if [[ ! -f ~/.secrets/smtp.env ]]; then
    cat > ~/.secrets/smtp.env << 'EOF'
# smtp2go credentials -- fill these in before starting the stack
SMTP_FROM_EMAIL=alertmanager@am180.us
SMTP_USERNAME=CHANGE_ME
SMTP_PASSWORD=CHANGE_ME
EOF
    chmod 600 ~/.secrets/smtp.env
    warn "Created ~/.secrets/smtp.env -- fill in credentials before starting stack."
else
    log "~/.secrets/smtp.env already exists."
fi

# ---------------------------------------------------------------------------
# 6. .env check
# ---------------------------------------------------------------------------
if grep -q "CHANGE_ME" "${STACK_DIR}/.env" 2>/dev/null; then
    warn ".env still has CHANGE_ME placeholders -- edit it before starting:"
    warn "  nano ${STACK_DIR}/.env"
    warn "  Key fields: HOST_LAN_IP, HOST_HOSTNAME, PLEX_HOST, SMTP_SECRETS_FILE"
fi

echo ""
log "Setup complete. Next steps:"
echo "  1. Edit .env:              nano ${STACK_DIR}/.env"
echo "  2. Edit smtp secrets:      nano ~/.secrets/smtp.env"
echo "  3. Start AdGuard first:    cd /path/to/AdGuardHome && docker compose up -d"
echo "  4. Start observability:    cd ${STACK_DIR} && ./manage.sh start"
echo "  5. Open Grafana:           http://\$(grep HOST_LAN_IP .env | cut -d= -f2):3000"
