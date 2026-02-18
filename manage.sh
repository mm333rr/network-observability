#!/usr/bin/env bash
# =============================================================================
# manage.sh — NetworkObservability stack management
# Usage: ./manage.sh [start|stop|restart|status|logs|pull|clean]
# =============================================================================

set -euo pipefail

STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE=(docker compose -f "$STACK_DIR/docker-compose.yml")

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

case "${1:-help}" in
  start)
    log "Starting NetworkObservability stack..."
    "${COMPOSE[@]}" up -d
    log "Stack started. Services:"
    echo "  Grafana:        http://localhost:3000  (admin / changeme_on_first_login)"
    echo "  Prometheus:     http://localhost:9090"
    echo "  Alertmanager:   http://localhost:9093"
    echo "  Loki:           http://localhost:3100"
    echo "  Promtail UI:    http://localhost:9080"
    echo "  Telegraf:       http://localhost:9273/metrics"
    ;;
  stop)
    log "Stopping stack..."
    "${COMPOSE[@]}" down
    log "Stack stopped. Data volumes preserved."
    ;;
  restart)
    log "Restarting stack..."
    "${COMPOSE[@]}" down
    "${COMPOSE[@]}" up -d
    log "Stack restarted."
    ;;
  status)
    "${COMPOSE[@]}" ps
    ;;
  logs)
    SERVICE="${2:-}"
    if [[ -n "$SERVICE" ]]; then
      "${COMPOSE[@]}" logs -f --tail=100 "$SERVICE"
    else
      "${COMPOSE[@]}" logs -f --tail=50
    fi
    ;;
  pull)
    log "Pulling latest images..."
    "${COMPOSE[@]}" pull
    warn "Run './manage.sh restart' to apply updated images."
    ;;
  clean)
    warn "This will remove ALL containers and volumes (DATA WILL BE DELETED). Continue? [y/N]"
    read -r confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      "${COMPOSE[@]}" down -v
      log "Stack and volumes removed."
    else
      log "Aborted."
    fi
    ;;
  help|*)
    echo "Usage: $0 {start|stop|restart|status|logs [service]|pull|clean}"
    echo ""
    echo "  start    — Start all services"
    echo "  stop     — Stop all services (data preserved)"
    echo "  restart  — Restart all services"
    echo "  status   — Show container status"
    echo "  logs     — Tail logs (optionally for a specific service)"
    echo "  pull     — Pull updated images"
    echo "  clean    — Remove everything including data volumes"
    ;;
esac
