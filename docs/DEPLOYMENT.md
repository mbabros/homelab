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
- [x] **Karakeep**: Migrated & active on port `30000`
- [ ] **Paperless-ngx**: Ready in `stacks/paperless/`
- [ ] **WordPress**: Ready in `stacks/wordpress/`
- [ ] **Nextcloud**: Ready in `stacks/nextcloud/`

---

## 4. GitHub Actions CI/CD Workflow Setup

Create `.github/workflows/deploy.yml` in your homelab repository to automate deployment upon pushing changes to `main`:

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
        if: contains(github.event.head_commit.modified, 'stacks/wordpress/') || github.event_name == 'workflow_dispatch'
        run: |
          echo "Deploying WordPress stack via local Docker engine..."
          docker compose --env-file .env -f stacks/wordpress/docker-compose.yml up -d

      - name: Deploy Nextcloud Stack
        if: contains(github.event.head_commit.modified, 'stacks/nextcloud/') || github.event_name == 'workflow_dispatch'
        run: |
          echo "Deploying Nextcloud stack via local Docker engine..."
          docker compose --env-file .env -f stacks/nextcloud/docker-compose.yml up -d

      - name: Deploy Paperless Stack
        if: contains(github.event.head_commit.modified, 'stacks/paperless/') || github.event_name == 'workflow_dispatch'
        run: |
          echo "Deploying Paperless-ngx stack via local Docker engine..."
          docker compose --env-file .env -f stacks/paperless/docker-compose.yml up -d

      - name: Deploy Karakeep Stack
        if: contains(github.event.head_commit.modified, 'stacks/karakeep/') || github.event_name == 'workflow_dispatch'
        run: |
          echo "Deploying Karakeep stack via local Docker engine..."
          docker compose --env-file .env -f stacks/karakeep/docker-compose.yml up -d

      - name: Deploy Utilities Stack
        if: contains(github.event.head_commit.modified, 'stacks/utilities/') || github.event_name == 'workflow_dispatch'
        run: |
          echo "Deploying Utilities stack via local Docker engine..."
          docker compose --env-file .env -f stacks/utilities/docker-compose.yml up -d
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
