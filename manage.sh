#!/usr/bin/env bash
# =============================================================================
# manage.sh — NetworkObservability stack management
# Portable: works on macOS (Mac Pro) and Linux (Raspberry Pi / Ubuntu)
# Usage: ./manage.sh [start|stop|restart|status|logs|pull|clean|dns-check]
# =============================================================================
set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_CMD=(docker compose -f "${STACK_DIR}/docker-compose.yml")

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Load .env for HOST_LAN_IP display
ENV_FILE="${STACK_DIR}/.env"
HOST_LAN_IP="localhost"
[[ -f "$ENV_FILE" ]] && HOST_LAN_IP=$(grep '^HOST_LAN_IP=' "$ENV_FILE" \
    | cut -d= -f2 | tr -d '"' || echo "localhost")

case "${1:-help}" in
  start)
    log "Starting NetworkObservability stack..."
    "${COMPOSE_CMD[@]}" up -d
    echo ""
    log "Stack started. Access URLs:"
    echo "  Grafana:        http://${HOST_LAN_IP}:3000"
    echo "  Prometheus:     http://${HOST_LAN_IP}:9090"
    echo "  Alertmanager:   http://${HOST_LAN_IP}:9093"
    echo "  Loki:           http://${HOST_LAN_IP}:3100"
    echo "  Promtail UI:    http://${HOST_LAN_IP}:9080"
    echo "  Telegraf:       http://${HOST_LAN_IP}:9273/metrics"
    echo "  Node Exporter:  http://${HOST_LAN_IP}:9100/metrics"
    echo "  cAdvisor:       http://${HOST_LAN_IP}:8080"
    ;;

  stop)
    log "Stopping stack..."
    "${COMPOSE_CMD[@]}" down
    log "Stack stopped. Data volumes preserved."
    ;;

  restart)
    log "Restarting stack..."
    "${COMPOSE_CMD[@]}" down
    "${COMPOSE_CMD[@]}" up -d
    log "Stack restarted."
    ;;

  status)
    "${COMPOSE_CMD[@]}" ps
    ;;

  logs)
    SERVICE="${2:-}"
    if [[ -n "$SERVICE" ]]; then
      "${COMPOSE_CMD[@]}" logs -f --tail=100 "$SERVICE"
    else
      "${COMPOSE_CMD[@]}" logs -f --tail=50
    fi
    ;;

  pull)
    log "Pulling latest images..."
    "${COMPOSE_CMD[@]}" pull
    warn "Run './manage.sh restart' to apply updated images."
    ;;

  clean)
    warn "This will remove ALL containers and volumes (DATA WILL BE DELETED). Continue? [y/N]"
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      "${COMPOSE_CMD[@]}" down -v
      log "Stack and volumes removed."
    else
      log "Aborted."
    fi
    ;;

  dns-check)
    log "Testing DNS resolution from each container..."
    PASS=0; FAIL=0
    for svc in prometheus grafana loki alertmanager promtail telegraf cadvisor node-exporter; do
      result=$(docker exec "$svc" sh -c \
        'getent hosts grafana.capes.local 2>/dev/null || nslookup grafana.capes.local 2>/dev/null | grep "Address:" | tail -1' \
        2>/dev/null | tr -s ' ')
      if echo "$result" | grep -qE '192\.168\.1\.[0-9]+'; then
        echo "  [OK]   $svc -> $result"
        PASS=$((PASS+1))
      else
        echo "  [FAIL] $svc -> ${result:-no response}"
        FAIL=$((FAIL+1))
      fi
    done
    echo ""
    log "DNS check: $PASS passed, $FAIL failed"
    [[ "$FAIL" -eq 0 ]] || { err "Failed containers can't resolve .capes.local -- is AdGuard running?"; exit 1; }
    ;;

  help|*)
    echo "Usage: $0 {start|stop|restart|status|logs [service]|pull|clean|dns-check}"
    echo ""
    echo "  start             Start all services"
    echo "  stop              Stop all services (data preserved)"
    echo "  restart           Full stack restart"
    echo "  status            Show container status table"
    echo "  logs [service]    Tail logs (all or specific service)"
    echo "  pull              Pull latest images (restart to apply)"
    echo "  clean             Remove containers + volumes (DESTRUCTIVE)"
    echo "  dns-check         Verify all containers resolve .capes.local"
    ;;
esac
