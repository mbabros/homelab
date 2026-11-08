---
title: Frequently Asked Questions (FAQ)
description: Answers to commonly asked questions about architecture, security, costs, and tooling.
---

### 1. Architecture & Cost

#### Why use Oracle Cloud Infrastructure (OCI) Always Free?
OCI provides an Ampere A1 ARM compute instance with 4 OCPUs, 24GB of RAM, 200GB NVMe storage, and a static IPv4 address permanently free of charge. This is ideal for running an always-on public reverse proxy without recurring cloud hosting fees.

#### How much does this entire infrastructure cost to run?
* **Domain Name (e.g. Cloudflare Registrar):** ~$10 / year.
* **Oracle Cloud Gateway:** $0 (Always Free Tier).
* **Cloudflare DNS & DDoS Mitigation:** $0 (Free Tier).
* **Tailscale WireGuard Mesh:** $0 (Tailscale Free Tier supports up to 3 users and 100 devices).
* **Electricity for Mac mini M2:** ~$1.50 – $2.50 / month (~10-15W average consumption).
* **Total Estimated Cost:** Under **$35 / year** for enterprise-grade self-hosting.

---

### 2. Network & Security

#### Why not port forward 80 and 443 directly on the home router?
Opening router ports exposes your residential IP address to public scans, automated botnets, and DDoS attacks. Furthermore, many residential ISPs use Carrier-Grade NAT (CGNAT) or actively block inbound port 80/443. Using an OCI gateway with Tailscale completely bypasses CGNAT and leaves **0 open ports** on your home network.

#### How does Let's Encrypt issue certificates if port 80 is not open at home?
Caddy utilizes the **Cloudflare DNS-01 ACME challenge**. Caddy communicates with the Cloudflare DNS API to temporarily write a `_acme-challenge` TXT record to prove domain ownership. Let's Encrypt queries Cloudflare's authoritative nameservers, validates the TXT record, and issues the wildcard certificate without ever touching port 80.

#### Does Tailscale add significant latency?
Tailscale establishes direct peer-to-peer WireGuard connections via UDP hole punching. Traffic travels directly between the OCI cloud gateway and your home node over the public internet, adding negligible overhead (typically 1–3ms over bare IP transit).

---

### 3. Applications & Infrastructure

#### Why choose Caddy over Nginx or Traefik?
1. **Automatic HTTPS:** Let's Encrypt certificate issuance, renewal, and OCSP stapling are built-in and enabled by default.
2. **Modern Protocols:** Native HTTP/3 (QUIC) support out of the box.
3. **Readable Configuration:** Caddyfiles are concise and human-readable compared to complex Nginx directives.
4. **Memory Safety:** Written in Go, eliminating entire classes of buffer overflow vulnerabilities.

#### Why use Apple Silicon (Mac mini) over an old x86 server or Raspberry Pi?
* **Compared to Raspberry Pi:** A Raspberry Pi has limited I/O bandwidth, SD card corruption risks, and insufficient compute for heavy tasks like video transcoding, OCR (Paperless-ngx), or LLM indexing.
* **Compared to x86 Servers:** Old enterprise rack servers consume 150–300W of electricity, generate heat, and produce fan noise. Apple Silicon Mac minis deliver desktop-class single-core and multi-core performance silently at 15 Watts.

#### How do backups work?
Database-backed services (PostgreSQL, MariaDB, SQLite) are scheduled to perform daily logical dumps via Coolify and cron jobs, backed up to off-site S3-compatible cloud storage (such as Backblaze B2 or Cloudflare R2).
