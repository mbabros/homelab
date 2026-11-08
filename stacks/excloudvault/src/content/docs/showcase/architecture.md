---
title: System Architecture & Topology
description: Comprehensive topological overview of the ExCloudVault.com zero-port hybrid private cloud architecture.
---

The **ExCloudVault.com** private cloud is an enterprise-grade, zero-trust hybrid self-hosted infrastructure. It merges the reliability of a free cloud edge gateway with high-density, energy-efficient Apple Silicon computing hardware at home, connected over an encrypted WireGuard mesh.

---

## 1. High-Level Component Topology

```mermaid
flowchart LR
    subgraph WAN["Public Internet"]
        Client["Client Browsers & APIs"]
    end

    subgraph DNS["Cloudflare Managed DNS"]
        Wildcard["Wildcard A-Record<br/>(*.mbabros.com)"]
        ShlinkDNS["Proxied A-Record<br/>(shlink.mbabros.com)"]
        ApexDNS["Direct CNAME<br/>(mbabros.com)"]
    end

    subgraph Edge["OCI Edge Reverse Proxy VM"]
        FW["UFW Firewall<br/>80, 443/tcp, 443/udp"]
        Caddy["Caddy Proxy & Wildcard SSL<br/>(Cloudflare DNS-01 ACME)"]
        Kuma["Uptime Kuma v2.5.9<br/>Host Port 3001"]
        Shlink["Shlink v5.1.8 & MariaDB 10.11<br/>Docker Net: shlink:8080"]
    end

    subgraph Mesh["Tailscale Encrypted Mesh (WireGuard)"]
        TS_Tunnel["100.x.y.z Private Overlay Tunnel"]
    end

    subgraph MacMini["Mac mini Primary Homelab Node"]
        Coolify["Coolify PaaS Controller<br/>:8008 UI · :6001 WS · :6002 Term"]
        Dedicated["Dedicated Services<br/>Nextcloud · Karakeep · Microbin..."]
        Cosmos["Cosmos Cloud Gateway (:443)<br/>Catch-All Reverse Proxy"]
    end

    subgraph Secondary["Secondary Homelab Node"]
        Node2["Photos (:2283)<br/>Office (:11080)"]
    end

    subgraph Cloud["External Cloud Edge"]
        Vercel["Vercel Edge Platform<br/>mbabros.vercel.app"]
    end

    %% Ingress Connections
    Client --> DNS
    ApexDNS --> Cloud
    Wildcard -->|"Public Ingress"| FW
    ShlinkDNS -->|"Cloudflare Proxied"| FW
    FW --> Caddy

    %% Edge Internal Dispatches
    Caddy -->|"Local Docker Network"| Shlink
    Caddy -->|"Local Port 3001"| Kuma
    Caddy -->|"Upstream Forward"| Vercel

    %% Mesh Dispatches
    Caddy -->|"WireGuard Overlay"| TS_Tunnel
    TS_Tunnel --> MacMini
    TS_Tunnel --> Secondary
```

---

## 2. Infrastructure Pillars

### A. Edge Gateway (Oracle Cloud Infrastructure Always-Free VM)
* **Compute:** OCI Always-Free ARM Ampere A1 (4 OCPUs, 24GB RAM, Ubuntu 22.04 LTS).
* **Ingress Engine:** Caddy with custom Cloudflare DNS module built-in via `xcaddy`.
* **Zero HTTP Validation:** Wildcard certificates (`*.mbabros.com`) are generated via Let's Encrypt using the Cloudflare DNS-01 ACME challenge. Port 80 is never used for domain validation.
* **Internal Health Monitoring:** Exposes a local healthcheck endpoint at `http://<OCI_VM_INTERNAL_IP>/healthz` returning HTTP 200 `"ok"`, polled by Uptime Kuma for heartbeat verification.

### B. Encrypted Mesh Overlay (Tailscale WireGuard)
* **Network Fabric:** Tailscale point-to-point mesh (`100.x.y.z`).
* **Zero Residential Inbound Ports:** The home router has **0 inbound ports forwarded**. CGNAT (Carrier-Grade NAT) and dynamic residential IPs are effortlessly handled via WireGuard stateful connections and Tailscale DERP relays.
* **Kernel-Level Encryption:** All transit between cloud reverse proxies and local homelab hardware is encrypted using ChaCha20-Poly1305.

### C. Apple Silicon PaaS Node (Mac mini M2)
* **Hardware:** Apple Silicon Mac mini with OrbStack lightweight container virtualization.
* **PaaS Engine:** [Coolify](https://coolify.io) running self-hosted container applications, databases, and scheduled backups.
* **Self-Hosted GitHub Runner:** Dedicated runner processing continuous integration and automated GitOps deployments directly on the hardware.

---

## 3. End-to-End SSL / TLS Boundary Model

```mermaid
flowchart LR
    Client["Public Client"]
    Caddy["Caddy Edge (OCI)"]
    TS_Net["Tailscale WireGuard Mesh"]
    Containers["Backend Apps (Mac mini / OCI)"]

    Client -->|"Public TLS (1.2 / 1.3 / QUIC)<br/>Let's Encrypt Wildcard (*.mbabros.com)"| Caddy
    Caddy -->|"Encrypted Kernel Tunnel<br/>ChaCha20-Poly1305 WireGuard"| TS_Net
    TS_Net -->|"Loopback / Local Container Port<br/>Plain HTTP or Internal Self-Signed TLS"| Containers
```

1. **Public Edge Termination:** All public traffic terminates TLS at Caddy on the OCI VM using a Let's Encrypt wildcard certificate (`*.mbabros.com`).
2. **Overlay Transit Encryption:** WireGuard encrypts all traffic traversing the public internet between the OCI VM and homelab nodes using ChaCha20-Poly1305 authenticated encryption.
3. **No Double-SSL Overhead:** Tailscale provides network-level security, allowing homelab containers to run in high-performance HTTP mode without managing per-container Let's Encrypt certificates.
