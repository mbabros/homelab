#!/bin/bash
# ============================================================
# Coolify Migration Master Script
# Cosmos Cloud → Coolify on OrbStack Docker Engine (macOS)
# ============================================================
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
HOMELAB_DIR="$(cd "$DIR/.." >/dev/null 2>&1 && pwd)"
COOLIFY_DIR="$HOMELAB_DIR/coolify"
STACKS_DIR="$HOMELAB_DIR/stacks"

# Colors
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'

info()    { echo -e "${GREEN}==>${RESET} $1"; }
warn()    { echo -e "${YELLOW}⚠️  $1${RESET}"; }
error()   { echo -e "${RED}✗  $1${RESET}"; exit 1; }
step()    { echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; echo -e "${GREEN}  $1${RESET}"; echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

check_prereqs() {
  step "Step 0: Checking prerequisites"
  command -v docker >/dev/null || error "Docker not found. Ensure OrbStack is running."
  command -v ssh-keygen >/dev/null || error "ssh-keygen not found."
  info "Docker version: $(docker --version)"
  info "Docker Compose version: $(docker compose version)"
}

setup_ssh() {
  step "Step 1: Setting up SSH key for Coolify → macOS host access"
  bash "$COOLIFY_DIR/setup-ssh.sh"
}

build_coolify() {
  step "Step 2: Building Coolify custom image"
  info "Building coolify-orbstack:latest..."
  docker compose -f "$COOLIFY_DIR/docker-compose.yml" build --no-cache
  info "Build complete."
}

start_coolify() {
  step "Step 3: Starting Coolify services (db + redis + app)"
  docker compose -f "$COOLIFY_DIR/docker-compose.yml" up -d
  info "Waiting for Coolify to become healthy..."
  local i=0
  while [ $i -lt 60 ]; do
    STATUS=$(docker inspect --format='{{.State.Health.Status}}' coolify 2>/dev/null || echo "starting")
    if [ "$STATUS" = "healthy" ]; then
      info "✅ Coolify is healthy!"
      break
    fi
    echo "   ...waiting (${i}s) - status: $STATUS"
    sleep 5
    i=$((i+5))
  done
  if [ "$STATUS" != "healthy" ]; then
    warn "Coolify healthcheck did not pass within 5 minutes. Check logs with: docker logs coolify"
  fi
  echo ""
  info "Coolify UI is available at: http://localhost:8008"
}

verify_volumes() {
  step "Step 4: Verifying existing Docker volumes are accessible"
  local VOLUMES=(
    "WordPress-config"
    "WordPress-mysql-data"
    "nextcloud-config"
    "nextcloud-custom_apps"
    "495f42bf34e380b2c80749daa47d7712bfc0b4c49edb65bfa68c64a695a93a66"
    "nextcloud-mariadb-data"
    "nextcloud-redis-data"
    "paperless-data"
    "paperless-media"
    "paperless-pgdata"
    "paperless-redisdata"
    "karakeep_data"
    "karakeep_meilisearch"
    "big-bear-microbin_data"
    "big-bear-nexterm-data"
  )
  local OK=true
  for vol in "${VOLUMES[@]}"; do
    if docker volume inspect "$vol" >/dev/null 2>&1; then
      info "  ✓ $vol"
    else
      warn "  ✗ MISSING: $vol"
      OK=false
    fi
  done
  if [ "$OK" = "false" ]; then
    warn "Some volumes are missing. Please verify before migrating those stacks."
  else
    info "All volumes present."
  fi
}

show_next_steps() {
  step "Setup Complete! Next Manual Steps"
  cat <<EOF

  1. Open Coolify UI:  http://localhost:8008
     - Register your admin account on first launch
     - Navigate to: Servers → Add Server
     - Choose "localhost" (SSH via key)
     - Host: host.docker.internal
     - Port: 22
     - User: \${SSH_USER:-\$USER}
     - Private key path inside container: /data/coolify/ssh/keys/id.\${SSH_USER:-\$USER}@host.docker.internal
       (or paste its contents from: \$COOLIFY_DIR/data/ssh/keys/id.\${SSH_USER:-\$USER}@host.docker.internal)

  2. Create a new Project for each application stack.

  3. Add each stack as a "Docker Compose" service, using the files at:
     - WordPress:   $STACKS_DIR/wordpress/docker-compose.yml
     - Nextcloud:   $STACKS_DIR/nextcloud/docker-compose.yml
     - Paperless:   $STACKS_DIR/paperless/docker-compose.yml
     - Karakeep:    $STACKS_DIR/karakeep/docker-compose.yml
     - Utilities:   $STACKS_DIR/utilities/docker-compose.yml

  4. Configure domains in Coolify's proxy settings (Traefik):
     - www.mbabros.com     → WordPress
     - nextcloud.mbabros.com → Nextcloud
     - paperless.mbabros.com → Paperless

  5. CUTOVER (when ready):
     bash $DIR/cutover.sh

  6. ROLLBACK (if needed for any reason):
     bash $DIR/rollback.sh

EOF
}

## ── Main ───────────────────────────────────────────────────
case "${1:-all}" in
  prereqs)   check_prereqs ;;
  ssh)       setup_ssh ;;
  build)     build_coolify ;;
  start)     start_coolify ;;
  volumes)   verify_volumes ;;
  all)
    check_prereqs
    setup_ssh
    build_coolify
    start_coolify
    verify_volumes
    show_next_steps
    ;;
  next-steps) show_next_steps ;;
  *)
    echo "Usage: $0 [prereqs|ssh|build|start|volumes|all|next-steps]"
    exit 1
    ;;
esac
