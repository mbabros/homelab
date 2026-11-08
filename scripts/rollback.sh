#!/bin/bash
# ============================================================
# Coolify → Cosmos Rollback Script
# Instantly restores Cosmos Cloud and its reverse proxy
# ============================================================
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
HOMELAB_DIR="$(cd "$DIR/.." >/dev/null 2>&1 && pwd)"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'
warn() { echo -e "${YELLOW}⚠️  $1${RESET}"; }
info() { echo -e "${GREEN}==>${RESET} $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   ROLLBACK: RESTORING COSMOS CLOUD                       ║"
echo "║   This will release ports 80/443 and restart Cosmos.     ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Stop coolify proxy / traefik if running on ports 80/443
if docker ps --format '{{.Names}}' | grep -q "coolify-proxy"; then
  info "Stopping Coolify proxy (coolify-proxy)..."
  docker stop coolify-proxy || true
fi

info "Starting cosmos-mongo-msj..."
docker start cosmos-mongo-msj || warn "cosmos-mongo-msj start reported error (may already be running)"

info "Starting cosmos-server..."
docker start cosmos-server || warn "cosmos-server start reported error (may already be running)"

# Check and optionally restore legacy containers if requested
if [ "$1" = "--restore-containers" ] || [ "$1" = "--all" ]; then
  info "Restoring legacy Cosmos containers..."
  PAIRS=(
    "cosmos-legacy-wordpress:WordPress"
    "cosmos-legacy-wordpress-mysql:WordPress-mysql"
    "cosmos-legacy-nextcloud:nextcloud"
    "cosmos-legacy-nextcloud-mariadb:nextcloud-mariadb"
    "cosmos-legacy-nextcloud-redis:nextcloud-redis"
  )
  for pair in "${PAIRS[@]}"; do
    legacy="${pair%%:*}"
    original="${pair##*:}"
    if docker ps -a --format '{{.Names}}' | grep -qx "$legacy"; then
      info "Restoring $legacy -> $original..."
      docker rename "$legacy" "$original" 2>/dev/null || true
      docker start "$original" 2>/dev/null || true
    fi
  done
fi

info "Waiting 5 seconds for Cosmos reverse proxy to bind ports 80 & 443..."
sleep 5

info "Current status of Cosmos containers:"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep cosmos

echo ""
info "✅ Rollback complete! Cosmos Cloud is back online and handling traffic."
info "   Dashboard: https://cosmos.mbabros.com or http://localhost"
