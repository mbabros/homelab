# AppFlowy Cloud Stack

[AppFlowy](https://appflowy.io/) is an open-source, privacy-first Notion alternative featuring offline support, AI integration, collaborative document editing, Kanban boards, and grid databases.

This directory contains the production-hardened configuration for self-hosting **AppFlowy Cloud v0.20+** orchestrated via Coolify and OrbStack Docker Engine on macOS Apple Silicon.

---

## 1. Stack Deployment Details

* **Service Type:** Coolify One-Click Compose Stack
* **Coolify UUID:** `nh7na8gkk8v7o5djlz2bwola`
* **Public Domain:** [`https://appflowy.mbabros.com`](https://appflowy.mbabros.com)
* **Admin Console:** [`https://appflowy.mbabros.com/console`](https://appflowy.mbabros.com/console)
* **Web App Client:** [`https://appflowy.mbabros.com/app`](https://appflowy.mbabros.com/app) (or root `/`)
* **Host Ports:**
  * `30020:80` (Nginx Gateway: routes API, GoTrue Auth, WebSocket, Presigned MinIO, and Admin Console)
  * `30021:80` (AppFlowy Web App Client container directly)

---

## 2. Multi-Container Architecture (v0.20)

AppFlowy Cloud v0.20 is composed of 10 microservices working together:

| Container Name | Image | Purpose / Role |
| :--- | :--- | :--- |
| `nginx` | `nginx:1.29.2` | High-performance reverse proxy gateway routing web traffic, REST API, WebSockets, GoTrue, and S3 presigned uploads. |
| `appflowy_web` | `appflowyinc/appflowy_web:0.20.11` | React/Vite single-page web workspace enabling in-browser document editing and collaboration. |
| `admin_frontend` | `appflowyinc/admin_frontend:latest` | Next.js server administration dashboard for managing workspaces, users, invitations, and telemetry. |
| `appflowy_cloud` | `appflowyinc/appflowy_cloud:0.20.5` | Core high-performance Rust backend exposing REST endpoints, document sync, and access control. |
| `gotrue` | `appflowyinc/gotrue:latest` | Supabase GoTrue authentication engine issuing signed JWTs and managing passwordless/password logins. |
| `appflowy_worker` | `appflowyinc/appflowy_worker:0.20.5` | Asynchronous worker processing background import jobs, indexing, and mail deliveries. |
| `ai` | `appflowyinc/appflowy_ai:0.9.149` | Python AI service providing OpenAI/local LLM integration and semantic embeddings. |
| `minio` | `pgsty/silo:RELEASE.2026-10-15T00-00-00Z` | S3-compatible high-performance object storage for images, file attachments, and document blobs. |
| `postgres` | `pgvector/pgvector:pg16` | PostgreSQL 16 database storing relational data, auth schemas, and vector embeddings (`pgvector`). |
| `redis` | `redis:8.2.2-alpine3.22` | In-memory key-value store for session caching, worker queues, and pub/sub messaging. |

---

## 3. Client vs. Server Version Compatibility (Crucial)

> [!IMPORTANT]
> **Client Version Constraint:**
> Modern AppFlowy desktop and mobile clients (**v0.15.0+**) implement the **Spaces Architecture** and require **AppFlowy Cloud v0.20+**.

### The "You can't use that feature here" Error
If an AppFlowy mobile client (iOS / Android) or desktop client (macOS / Linux / Windows) connects to an older server (such as `0.9.x`):
- Modern clients issue requests to:
  - `POST /api/workspace/{id}/view/{view_id}` (Document creation inside spaces)
  - `GET /notifications/unread-count` (Notification counts)
  - `POST /api/workspace/{id}/space` (Spaces management)
- On server versions `0.9.x`, these endpoints did not exist and returned `404 Not Found`.
- The client UI surfaces this 404 as: **"You can't use that feature here"** whenever the user clicks the `+` sign next to "Private" or "Workspace".

### Resolution
- Always ensure `appflowy_cloud` is at least version `0.20.5` and `appflowy_web` is `0.20.11`.
- When updating images, `sqlx` migrations run automatically on container startup to upgrade the PostgreSQL schema.
- Required startup parameter:
  ```yaml
  APPFLOWY_S3_PRESIGNED_URL_ENDPOINT: "https://appflowy.mbabros.com/minio-api"
  APPFLOWY_SEARCH_ENABLED: "false"
  APPFLOWY_WEB_URL: "https://appflowy.mbabros.com"
  ```

---

## 4. Nginx Reverse Proxy Architecture

The Nginx configuration (`nginx/nginx.conf`) handles intelligent path-based routing across the container network:

```mermaid
flowchart TD
    Client["Client Traffic (https://appflowy.mbabros.com)"]
    Nginx["Nginx Gateway (:80 in container / :30020 host)"]

    Client --> Nginx

    Nginx -->|"/" & "/app"| Web["appflowy_web:80\n(Web Workspace)"]
    Nginx -->|"/console"| Admin["admin_frontend:3000\n(Admin Console)"]
    Nginx -->|"/api"| API["appflowy_cloud:8000\n(Rust Core API)"]
    Nginx -->|"/ws & /ws/v2"| WS["appflowy_cloud:8000\n(WebSocket Upgrades)"]
    Nginx -->|"/gotrue/"| Auth["gotrue:9999\n(Authentication)"]
    Nginx -->|"/minio-api/"| S3["minio:9000\n(S3 Presigned Uploads)"]
    Nginx -->|"/health"| Health["HTTP 200 'healthy'"]
```

### Key Routing Directives

1. **Web Workspace (`/` & `/app`)**:
   - Proxies to `appflowy_web:80`.
   - **Do NOT** redirect `/` to `/console`. Redirecting `/` to `/console` locks normal non-administrator users into the administrative dashboard login screen.
2. **Server Administration Console (`/console`)**:
   - Proxies to `admin_frontend:3000`.
   - Accessible only to super administrators.
3. **Presigned S3 Uploads (`/minio-api/`)**:
   - Presigned S3 URLs generated by AppFlowy Cloud point to `https://appflowy.mbabros.com/minio-api/...`.
   - Nginx strips `/minio-api/` and rewrites the `Host` header to `minio:9000` to satisfy MinIO's AWS signature v4 validation:
     ```nginx
     location /minio-api/ {
         proxy_pass http://minio:9000;
         proxy_set_header Host minio:9000;
         rewrite ^/minio-api/(.*) /$1 break;
         client_max_body_size 0;
     }
     ```
4. **WebSocket Sync (`/ws` and `/ws/v2`)**:
   - Configured with `Upgrade $http_upgrade` and `Connection "Upgrade"` with an 86400s timeout for persistent realtime document collaboration.

---

## 5. Authentication & GoTrue Role Requirements

AppFlowy Cloud separates standard users from instance administrators using GoTrue JWT claims and database roles.

### "Only admin can perform this action" (Error 1012)
If you attempt to invite users or access administrative settings in `/console` and receive:
`"Only admin can perform this action"` (Code: 1012), your user lacks super admin privileges in GoTrue.

### Promoting a User to Super Admin
Standard users are assigned `role = 'authenticated'` or `role = 'admin'`. However, GoTrue requires `role = 'supabase_admin'` AND `is_super_admin = true`:

```bash
docker exec -i postgres-nh7na8gkk8v7o5djlz2bwola psql -U appflowy -d appflowy -c "
UPDATE auth.users 
SET role = 'supabase_admin', 
    is_super_admin = true 
WHERE email = 'admin@mbabros.com';
"
```

Verify the role assignment:
```bash
docker exec -i postgres-nh7na8gkk8v7o5djlz2bwola psql -U appflowy -d appflowy -c "
SELECT id, email, role, is_super_admin FROM auth.users;
"
```

---

## 6. SMTP Mailer & Email Notifications

For invitations, password resets, and notifications, SMTP must be configured in both `appflowy_cloud` and `gotrue`.

### Gmail SMTP Protocol Requirements
- **Port 465 (Direct SSL / Wrapper)**:
  `appflowy_cloud` and `appflowy_worker` require direct SSL wrapper mode. Port 587 with STARTTLS will fail with:
  `No compatible authentication mechanism was found`.
- **Environment Configuration**:
  ```ini
  APPFLOWY_MAILER_SMTP_HOST=smtp.gmail.com
  APPFLOWY_MAILER_SMTP_PORT=465
  APPFLOWY_MAILER_SMTP_USERNAME=your_username@gmail.com
  APPFLOWY_MAILER_SMTP_EMAIL=admin@mbabros.com
  APPFLOWY_MAILER_SMTP_PASSWORD=your_16_char_google_app_password
  APPFLOWY_MAILER_SMTP_TLS_KIND=wrapper
  ```
- **GoTrue Settings**:
  ```ini
  GOTRUE_SMTP_HOST=smtp.gmail.com
  GOTRUE_SMTP_PORT=587
  GOTRUE_SMTP_USER=your_username@gmail.com
  GOTRUE_SMTP_PASS=your_16_char_google_app_password
  GOTRUE_SMTP_ADMIN_EMAIL=admin@mbabros.com
  GOTRUE_MAILER_AUTOCONFIRM=true
  ```

---

## 7. Connecting Official Desktop and Mobile Apps

1. Download the AppFlowy application from [appflowy.io/download](https://appflowy.io/download) or Apple App Store / Google Play Store.
2. In the app, navigate to **Settings** -> **Cloud / Sync** (or select **Self-Hosted** on the login screen).
3. Set **AppFlowy Cloud URL** to:
   ```text
   https://appflowy.mbabros.com
   ```
4. Enter your registered email address and password (or click magic link).
5. You will have full access to Spaces, private documents, databases, and real-time synchronization.

---

## 8. Operational Runbook & Maintenance

### Verify Service Health
```bash
# Nginx gateway health
curl -i http://127.0.0.1:30020/health

# AppFlowy Cloud Rust API health
curl -i http://127.0.0.1:30020/api/health

# GoTrue Authentication health
curl -i http://127.0.0.1:30020/gotrue/health
```

### Reload Nginx Configuration without Downtime
If you edit `stacks/appflowy/nginx/nginx.conf`:
```bash
cp stacks/appflowy/nginx/nginx.conf /Users/aru/homelab/coolify/data/services/nh7na8gkk8v7o5djlz2bwola/nginx/nginx.conf
docker exec nginx-nh7na8gkk8v7o5djlz2bwola nginx -s reload
```

### Database Backup & Restore
Backup current database:
```bash
docker exec -t postgres-nh7na8gkk8v7o5djlz2bwola pg_dump -U appflowy appflowy > appflowy_backup_$(date +%Y%m%d_%H%M%S).sql
```

Restore database:
```bash
docker exec -i postgres-nh7na8gkk8v7o5djlz2bwola psql -U appflowy -d appflowy < appflowy_backup_20261108_121600.sql
```

### View Realtime Logs
```bash
# Rust API Server
docker logs -f appflowy_cloud-nh7na8gkk8v7o5djlz2bwola --tail 100

# Authentication Service
docker logs -f gotrue-nh7na8gkk8v7o5djlz2bwola --tail 100

# Background Worker
docker logs -f appflowy_worker-nh7na8gkk8v7o5djlz2bwola --tail 100

# Gateway Proxy
docker logs -f nginx-nh7na8gkk8v7o5djlz2bwola --tail 100
```
