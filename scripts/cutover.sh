#!/bin/bash
# ============================================================
# Cosmos → Coolify Cutover Script
# Run ONLY when all stacks are verified in Coolify
# ============================================================
set -e
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
HOMELAB_DIR="$(cd "$DIR/.." >/dev/null 2>&1 && pwd)"

PROXY_DIR="$HOMELAB_DIR/coolify/data/proxy"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'
warn() { echo -e "${YELLOW}⚠️  $1${RESET}"; }
info() { echo -e "${GREEN}==>${RESET} $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   COSMOS → COOLIFY CUTOVER                               ║"
echo "║   This will STOP cosmos-server (without deleting it)     ║"
echo "║   and hand ports 80/443 to Coolify Traefik proxy.        ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
warn "BEFORE proceeding, confirm:"
warn "  ✓ All stacks are deployed and healthy in Coolify"
warn "  ✓ You have verified domains resolve correctly via Coolify"
warn "  ✓ You can rollback at any time by running: bash scripts/rollback.sh"
echo ""
read -p "Type 'CUTOVER' to proceed: " CONFIRM
if [ "$CONFIRM" != "CUTOVER" ]; then
  echo "Aborted."
  exit 1
fi

info "Stopping cosmos-server (preserving container for rollback)..."
docker stop cosmos-server 2>/dev/null || warn "cosmos-server was not running"

info "Stopping cosmos-mongo-msj (preserving container for rollback)..."
docker stop cosmos-mongo-msj 2>/dev/null || warn "cosmos-mongo-msj was not running"

info "Starting Coolify Traefik proxy on ports 80/443..."
if [ -f "$PROXY_DIR/docker-compose.yml" ]; then
  docker compose -f "$PROXY_DIR/docker-compose.yml" up -d
else
  warn "Proxy compose file not found at $PROXY_DIR/docker-compose.yml"
fi

info "Connecting coolify-proxy to application networks..."
for network in $(docker inspect $(docker ps -a --filter label=coolify.managed=true --format "{{.ID}}") --format='{{range $network, $_ := .NetworkSettings.Networks}}{{println $network}}{{end}}' 2>/dev/null | sort -u); do
    if [ -z "$network" ] || [ "$network" = "bridge" ] || [ "$network" = "host" ] || [ "$network" = "none" ] || [ "$network" = "default" ]; then
        continue
    fi
    if docker network inspect "$network" >/dev/null 2>&1; then
        docker network connect "$network" coolify-proxy 2>/dev/null || true
    fi
done

info "Waiting 5 seconds for proxy to settle..."
sleep 5

info "Checking active port bindings..."
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep -E "coolify-proxy|traefik"

echo ""
info "✅ Cutover complete! Test your endpoints:"
info "   curl -I https://www.mbabros.com"
info "   curl -I https://nextcloud.mbabros.com"
info "   curl -I https://paperless.mbabros.com"
echo ""
info "ℹ️  If you encounter any issues and need to revert, run:"
info "   bash $DIR/rollback.sh"
