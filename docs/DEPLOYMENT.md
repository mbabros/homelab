# Homelab Deployment & GitOps Runbook

This guide walk you through installing the GitHub Actions Self-Hosted Runner on your Mac Mini, configuring Coolify for Git-based deployments, and setting up automated CI/CD for your homelab stacks.

---

## 1. Prerequisites

Before beginning, ensure the following are running on your Mac Mini:
- **OrbStack**: Docker engine active (`docker ps` works without sudo).
- **Tailscale**: Active connection to your tailnet.
- **Coolify**: Running at `http://localhost:8008` (via `cd coolify && docker compose up -d`).

---

## 2. GitHub Actions Self-Hosted Runner Status

The self-hosted runner is **installed and active** as a persistent macOS LaunchAgent service:
- **Service Name**: `actions.runner.mbabros-homelab.mac-mini-homelab.plist`
- **Location**: `~/actions-runner/`
- **Labels**: `self-hosted, macmini, homelab, apple-silicon`
- **Architecture**: Outbound long-poll over HTTPS/WSS (zero open ports required on router or proxy)

If you ever need to restart or manage the runner service:
```bash
cd ~/actions-runner
./svc.sh status   # Check runner status
./svc.sh stop     # Stop runner service
./svc.sh start    # Start runner service
```

---

## 3. Coolify Configuration & Project Hierarchy

### Project & Server Setup
1. **Server Registration (Complete)**:
   - Coolify connects to the local Mac Mini host via `<host-user>@host.docker.internal:22` (e.g. `${USER}@host.docker.internal`).
   - Validated for OrbStack Docker Engine without requiring `sudo`.
   - Data directory configured to `~/homelab/coolify/data` via `BASE_CONFIG_PATH`.
2. **Project Structure**:
   - Master Project: **Homelab**
   - Environment: **production**

### Migrating Stacks into Coolify
Each stack compose manifest in `stacks/` is imported into the **Homelab** project under **production**:
1. Go to **Projects → Homelab → production → + New Resource → Docker Compose**.
2. Supply the compose YAML and configure environment variables from [`~/homelab/.env`](../.env).
3. Ensure the legacy Cosmos container is stopped/renamed before deployment to release port bindings:
   ```bash
   docker stop <container-name>
   docker rename <container-name> cosmos-legacy-<container-name>
   ```
4. Deploy the resource in Coolify.

**Migration Progress:**
- [x] **Utilities**: Migrated & active (`microbin`, `dashy`, `nexterm`)
- [x] **mbabros.com**: Built & active on port `30010`
- [x] **ExCloudVault**: Active on port `30010`
- [x] **Karakeep**: Migrated & active on port `30000`
- [x] **Joplin Server**: Active on port `22300`
- [x] **AppFlowy Cloud**: Active on port `30020` & `30021` (v0.20+ with Spaces)
- [ ] **Paperless-ngx**: Ready in `stacks/paperless/`
- [ ] **WordPress**: Ready in `stacks/wordpress/`
- [ ] **Nextcloud**: Ready in `stacks/nextcloud/`

---

## 4. GitHub Actions CI/CD Workflow Setup

The repository utilizes [`.github/workflows/deploy.yml`](../.github/workflows/deploy.yml) to automate deployment on pushes to `main` with smart change detection:

```yaml
name: Deploy Homelab Stacks

on:
  push:
    branches:
      - main
    paths:
      - 'stacks/**'
      - 'coolify/**'
  workflow_dispatch:

jobs:
  deploy:
    runs-on: [self-hosted, macmini]
    steps:
      - name: Checkout Code
        uses: actions/checkout@v4

      - name: Deploy WordPress Stack
        if: contains(toJson(github.event.commits), 'stacks/wordpress/') || contains(toJson(github.event.head_commit), 'stacks/wordpress/') || github.event_name == 'workflow_dispatch'
        run: |
          echo "Deploying WordPress stack via local OrbStack Docker..."
          ENV_ARGS=""
          [ -f .env ] && ENV_ARGS="--env-file .env"
          docker compose $ENV_ARGS -f stacks/wordpress/docker-compose.yml up -d

      - name: Deploy Nextcloud Stack
        if: contains(toJson(github.event.commits), 'stacks/nextcloud/') || contains(toJson(github.event.head_commit), 'stacks/nextcloud/') || github.event_name == 'workflow_dispatch'
        run: |
          echo "Deploying Nextcloud stack via local OrbStack Docker..."
          ENV_ARGS=""
          [ -f .env ] && ENV_ARGS="--env-file .env"
          docker compose $ENV_ARGS -f stacks/nextcloud/docker-compose.yml up -d

      - name: Deploy Paperless Stack
        if: contains(toJson(github.event.commits), 'stacks/paperless/') || contains(toJson(github.event.head_commit), 'stacks/paperless/') || github.event_name == 'workflow_dispatch'
        run: |
          echo "Deploying Paperless-ngx stack via local OrbStack Docker..."
          ENV_ARGS=""
          [ -f .env ] && ENV_ARGS="--env-file .env"
          docker compose $ENV_ARGS -f stacks/paperless/docker-compose.yml up -d

      - name: Deploy Karakeep Stack
        if: contains(toJson(github.event.commits), 'stacks/karakeep/') || contains(toJson(github.event.head_commit), 'stacks/karakeep/') || github.event_name == 'workflow_dispatch'
        run: |
          echo "Deploying Karakeep stack via local OrbStack Docker..."
          ENV_ARGS=""
          [ -f .env ] && ENV_ARGS="--env-file .env"
          docker compose $ENV_ARGS -f stacks/karakeep/docker-compose.yml up -d

      - name: Deploy Utilities Stack
        if: contains(toJson(github.event.commits), 'stacks/utilities/') || contains(toJson(github.event.head_commit), 'stacks/utilities/') || github.event_name == 'workflow_dispatch'
        run: |
          echo "Deploying Utilities stack via local OrbStack Docker..."
          ENV_ARGS=""
          [ -f .env ] && ENV_ARGS="--env-file .env"
          docker compose $ENV_ARGS -f stacks/utilities/docker-compose.yml up -d

      - name: Deploy ExCloudVault Stack
        if: contains(toJson(github.event.commits), 'stacks/excloudvault/') || contains(toJson(github.event.head_commit), 'stacks/excloudvault/') || github.event_name == 'workflow_dispatch'
        run: |
          echo "Deploying ExCloudVault stack on Mac Mini..."
          cd stacks/excloudvault
          docker build -t excloudvault-web:latest .
          COOLIFY_COMPOSE_DIR="/Users/aru/homelab/coolify/data/services/acxgaouv9ifw9puh1lohcazo"
          if [ -d "$COOLIFY_COMPOSE_DIR" ] && [ -f "$COOLIFY_COMPOSE_DIR/docker-compose.yml" ]; then
            echo "Deploying via Coolify compose definition..."
            docker compose --project-directory "$COOLIFY_COMPOSE_DIR" -f "$COOLIFY_COMPOSE_DIR/docker-compose.yml" up -d --force-recreate
          else
            echo "Deploying via repo compose definition..."
            docker compose up -d --force-recreate
          fi
          for i in {1..15}; do
            STATUS=$(curl -s http://127.0.0.1:30010/healthz || true)
            if echo "$STATUS" | grep -q "ok"; then
              echo "✅ ExCloudVault service is healthy and responding!"
              break
            fi
            echo "Waiting for container startup... ($i/15)"
            sleep 2
          done

      - name: Deploy Joplin Stack
        if: contains(toJson(github.event.commits), 'stacks/joplin/') || contains(toJson(github.event.head_commit), 'stacks/joplin/') || github.event_name == 'workflow_dispatch'
        run: |
          echo "Deploying Joplin Server stack via Coolify / OrbStack..."
          COOLIFY_JOPLIN_DIR="/Users/aru/homelab/coolify/data/services/1fpxozg7p89dbgvutid0fkbj"
          if [ -d "$COOLIFY_JOPLIN_DIR" ] && [ -f "$COOLIFY_JOPLIN_DIR/docker-compose.yml" ]; then
            echo "Deploying via Coolify compose definition..."
            docker compose --project-directory "$COOLIFY_JOPLIN_DIR" -f "$COOLIFY_JOPLIN_DIR/docker-compose.yml" up -d
          else
            echo "Deploying via repo compose definition..."
            ENV_ARGS=""
            [ -f .env ] && ENV_ARGS="--env-file .env"
            docker compose $ENV_ARGS -f stacks/joplin/docker-compose.yml up -d
          fi

          echo "Verifying Joplin Server health..."
          for i in {1..15}; do
            STATUS=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: joplin.mbabros.com" http://127.0.0.1:22300/login || true)
            if [ "$STATUS" = "200" ]; then
              echo "✅ Joplin Server is responding with HTTP 200!"
              break
            fi
            echo "Waiting for Joplin server startup... ($i/15)"
            sleep 2
          done
          docker ps --filter "name=joplin" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

      - name: Deploy AppFlowy Stack
        if: contains(toJson(github.event.commits), 'stacks/appflowy/') || contains(toJson(github.event.head_commit), 'stacks/appflowy/') || github.event_name == 'workflow_dispatch'
        run: |
          echo "Deploying AppFlowy Cloud stack via Coolify / OrbStack..."
          COOLIFY_APPFLOWY_DIR="/Users/aru/homelab/coolify/data/services/nh7na8gkk8v7o5djlz2bwola"
          if [ -d "$COOLIFY_APPFLOWY_DIR" ] && [ -f "$COOLIFY_APPFLOWY_DIR/docker-compose.yml" ]; then
            echo "Syncing Nginx reverse proxy configuration to Coolify..."
            mkdir -p "$COOLIFY_APPFLOWY_DIR/nginx"
            cp stacks/appflowy/nginx/nginx.conf "$COOLIFY_APPFLOWY_DIR/nginx/nginx.conf"

            echo "Deploying via Coolify compose definition..."
            docker compose --project-directory "$COOLIFY_APPFLOWY_DIR" -f "$COOLIFY_APPFLOWY_DIR/docker-compose.yml" up -d
          else
            echo "Deploying via repo compose definition..."
            ENV_ARGS=""
            [ -f .env ] && ENV_ARGS="--env-file .env"
            docker compose $ENV_ARGS -f stacks/appflowy/docker-compose.yml up -d
          fi

          if docker ps -q --filter "name=nginx-nh7na8gkk8v7o5djlz2bwola" | grep -q .; then
            echo "Reloading Nginx configuration inside container..."
            docker exec nginx-nh7na8gkk8v7o5djlz2bwola nginx -s reload || true
          fi

          echo "Verifying AppFlowy Cloud stack health..."
          for i in {1..20}; do
            NGINX_HEALTH=$(curl -s http://127.0.0.1:30020/health || true)
            API_HEALTH=$(curl -s http://127.0.0.1:30020/api/health || true)
            GOTRUE_HEALTH=$(curl -s http://127.0.0.1:30020/gotrue/health || true)
            if [ "$NGINX_HEALTH" = "healthy" ] && [ "$API_HEALTH" = "OK" ]; then
              echo "✅ AppFlowy Nginx and Cloud API are healthy and responding!"
              break
            fi
            echo "Waiting for AppFlowy services... ($i/20)"
            sleep 3
          done
          docker ps --filter "name=nh7na8gkk8v7o5djlz2bwola" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

### Dual Deployment for mbabros.com (Coolify & Vercel)

The dedicated pipeline [`.github/workflows/deploy-mbabros.yml`](../.github/workflows/deploy-mbabros.yml) enables seamless dual deployment to either Coolify, Vercel, or both:

- **Triggering Deployments**:
  - Automatically builds and deploys on push to `stacks/mbabros/**`.
  - Can be manually triggered via **GitHub Actions → Run workflow**, selecting the target: `both`, `coolify`, or `vercel`.
- **Vercel Automation**:
  - Add your deploy hook or Vercel token under GitHub repository **Settings → Secrets and variables → Actions**:
    - `VERCEL_DEPLOY_HOOK`: Webhook URL generated in Vercel project settings.
    - `VERCEL_TOKEN`: Vercel personal access token (optional alternative).

---

## 5. Cutover from Cosmos Cloud to Coolify

The production cutover transitions public traffic from Cosmos Cloud to Coolify Traefik:

```bash
cd ~/homelab
bash scripts/cutover.sh
```

Type `CUTOVER` when prompted. This script:
1. Stops `cosmos-server` and `cosmos-mongo-msj` (preserving containers intact for zero data loss rollback).
2. Releases host ports `80` and `443`.
3. Launches Coolify's Traefik reverse proxy (`coolify-proxy`) bound to ports `80/443`.
4. Connects `coolify-proxy` to all active application stack Docker networks.
5. Verifies live port bindings and route availability.

---

## 6. Instant Rollback (If Needed)

If any issue arises and you need to restore Cosmos Cloud immediately:

```bash
cd ~/homelab
bash scripts/rollback.sh --restore-containers
```

This stops Coolify's Traefik proxy, starts `cosmos-server` and `cosmos-mongo-msj`, and restores any legacy Cosmos container names in ~5 seconds with zero data loss.

---

## 7. AppFlowy Cloud Operations & Troubleshooting Runbook

For complete operational details and architecture diagrams, refer to [`stacks/appflowy/README.md`](../stacks/appflowy/README.md).

### 7.1 Client Compatibility Guidelines
- **AppFlowy Mobile & Desktop v0.15+**: Must connect to AppFlowy Cloud **v0.20+**.
- Server versions below 0.20 will reject modern client Space endpoints with 404, surfacing as `"You can't use that feature here"` in the app.

### 7.2 Promoting an Admin User (Fixing Error 1012)
If inviting users or accessing administrative features triggers `"Only admin can perform this action"`:
```bash
docker exec -i postgres-nh7na8gkk8v7o5djlz2bwola psql -U appflowy -d appflowy -c "
UPDATE auth.users 
SET role = 'supabase_admin', 
    is_super_admin = true 
WHERE email = 'admin@mbabros.com';
"
```

### 7.3 Gmail SMTP Configuration (Direct SSL Port 465)
In Coolify or `stacks/appflowy/.env`:
- `APPFLOWY_MAILER_SMTP_PORT=465`
- `APPFLOWY_MAILER_SMTP_TLS_KIND=wrapper` (Port 587 with STARTTLS fails with `No compatible authentication mechanism was found`).

### 7.4 Reload Nginx Gateway Without Downtime
```bash
cp stacks/appflowy/nginx/nginx.conf /Users/aru/homelab/coolify/data/services/nh7na8gkk8v7o5djlz2bwola/nginx/nginx.conf
docker exec nginx-nh7na8gkk8v7o5djlz2bwola nginx -s reload
```

