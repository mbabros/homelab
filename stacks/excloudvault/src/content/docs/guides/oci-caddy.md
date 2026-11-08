---
title: 1. OCI Ingress & Caddy Wildcard SSL
description: Step-by-step guide to provisioning a cloud edge gateway on Oracle Cloud Infrastructure with Caddy and automated Cloudflare DNS-01 wildcard certificates.
---

In this blueprint, you will build the public edge ingress gateway using **Oracle Cloud Infrastructure (OCI)** and **Caddy**. This setup eliminates the need to expose your home router's IP address or open any inbound ports on your residential network.

---

## 1. Why OCI Always Free & Caddy?

* **Oracle Cloud Always Free Ampere A1:** Provides up to 4 Arm-based OCPUs, 24GB of RAM, and 200GB of storage with a static public IPv4 address at zero cost.
* **Caddy Reverse Proxy:** Memory-safe (written in Go), natively supports HTTP/3 (QUIC), and handles automatic TLS certificate generation and renewal.
* **Cloudflare DNS-01 ACME Challenge:** By issuing certificates using Cloudflare DNS API tokens, Caddy generates wildcard certificates (`*.yourdomain.com`) without requiring port 80 to be open for domain validation.

---

## 2. Prerequisites

1. An Oracle Cloud Infrastructure account.
2. A domain name with DNS managed by Cloudflare.
3. A Cloudflare API Token with the following permissions:
   * **Zone / DNS / Edit**
   * Scope: Include **All Zones** or your specific domain zone.

---

## 3. Provisioning the OCI Ampere Instance

1. In the OCI Console, navigate to **Compute > Instances > Create Instance**.
2. Select **Canonical Ubuntu 22.04 LTS** (or 24.04 LTS) minimal image.
3. Shape: Select **Ampere VM.Standard.A1.Flex** (e.g. 2 OCPUs, 12GB RAM).
4. Networking: Assign a public IPv4 address and attach an SSH key.
5. In the OCI Virtual Cloud Network (VCN) Ingress Security List, add rules allowing:
   * `22/tcp` (SSH)
   * `80/tcp` (HTTP)
   * `443/tcp` (HTTPS)
   * `443/udp` (HTTP/3 QUIC)

---

## 4. Deploying Caddy with Cloudflare DNS Support

To enable the Cloudflare DNS-01 plugin, Caddy must be built with `github.com/caddy-dns/cloudflare`. You can run the pre-built container or build it using `xcaddy`.

### Option A: Docker Compose Deployment (Recommended)

Create `/opt/caddy/docker-compose.yml`:

```yaml
services:
  caddy:
    image: ghcr.io/serfriz/caddy-cloudflare:latest
    container_name: caddy
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "443:443/udp" # HTTP/3 QUIC support
    environment:
      - CF_API_TOKEN=${CLOUDFLARE_API_TOKEN}
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy_data:/data
      - caddy_config:/config
    networks:
      - npm_net

networks:
  npm_net:
    name: nginx-proxy-manager_default
    external: true

volumes:
  caddy_data:
  caddy_config:
```

### Option B: Bare-Metal xcaddy Binary

```bash
# Install xcaddy
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/xcaddy/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-xcaddy-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/xcaddy/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-xcaddy.list
sudo apt update && sudo apt install -y xcaddy

# Build custom Caddy binary with Cloudflare plugin
xcaddy build --with github.com/caddy-dns/cloudflare
sudo mv caddy /usr/bin/caddy
```

---

## 5. Crafting the Production Caddyfile

Create your `Caddyfile`:

```nginx
{
    email admin@mbabros.com
    acme_dns cloudflare {$CF_API_TOKEN}
    servers {
        protocol {
            experimental_http3
        }
    }
}

# Health Check Probe for local monitoring (Option A)
:80 {
    @healthz path /healthz
    handle @healthz {
        respond "ok" 200
    }
    handle {
        redir https://{host}{uri} permanent
    }
}

# Wildcard Ingress block for internal homelab services
*.mbabros.com {
    tls {
        dns cloudflare {$CF_API_TOKEN}
    }

    # Coolify PaaS Controllers
    @coolify host coolify.mbabros.com
    handle @coolify {
        # Laravel Reverb WebSockets
        @ws_events path /app/*
        handle @ws_events {
            reverse_proxy 100.x.y.z:6001
        }
        # Interactive Web Terminal WebSockets
        @ws_term path /terminal/ws*
        handle @ws_term {
            reverse_proxy 100.x.y.z:6002
        }
        # Standard HTTP Dashboard
        handle {
            reverse_proxy 100.x.y.z:8008
        }
    }

    # Nextcloud Hub
    @nextcloud host nextcloud.mbabros.com
    handle @nextcloud {
        reverse_proxy 100.x.y.z:8080
    }

    # Cosmos Cloud Gateway (requires explicit Host header)
    @cosmos host cosmos.mbabros.com
    handle @cosmos {
        reverse_proxy 100.x.y.z:443 {
            transport http {
                tls_insecure_skip_verify
            }
            header_up Host cosmos.mbabros.com
        }
    }

    # Fallback Catch-All to Cosmos Router
    handle {
        reverse_proxy 100.x.y.z:443 {
            transport http {
                tls_insecure_skip_verify
            }
        }
    }
}
```

---

## 6. Verification & Certificate Check

Start Caddy and inspect the certificate handshake:

```bash
docker compose up -d
docker logs -f caddy
```

Expected log output:
```text
certificate obtained successfully {"identifier": "*.mbabros.com", "issuer": "acme-v02.api.letsencrypt.org-directory"}
server is listening only on the HTTPS port but has no TLS configuration for: :80
```

Verify TLS and HTTP/3 support from your local workstation:

```bash
curl -Iv --http3 https://uptime.mbabros.com/
```
