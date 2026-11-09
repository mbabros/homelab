# Joplin Server Stack

[Joplin Server](https://joplinapp.org/help/apps/server/) provides end-to-end encrypted synchronization, note sharing, and collaboration for Joplin desktop and mobile apps.

## Deployment Details

* **Service Type:** Coolify One-Click Compose Stack
* **Coolify UUID:** `1fpxozg7p89dbgvutid0fkbj`
* **Host Port:** `22300` (mapped to internal container port `22300`)
* **Database:** PostgreSQL 16 Alpine
* **Public Domain:** `https://joplin.mbabros.com`
* **Default Initial Admin:** `admin@localhost` / `admin` (change immediately after first login)

## Architecture & Reverse Proxy Flow

```
User (Browser / Joplin App)
       │
       ▼ https://joplin.mbabros.com
 Cloudflare Edge DNS (Wildcard A *.mbabros.com)
       │
       ▼ (Port 443 / Cloudflare TLS)
 OCI Gateway Caddy Reverse Proxy
       │
       ▼ (Tailscale Mesh :22300)
 Mac mini Docker Container (joplin-server)
       │
       ▼ (Internal Docker Network)
 PostgreSQL 16 Container (joplin-postgres)
```
