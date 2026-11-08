import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import starlightBlog from 'starlight-blog';

// https://astro.build/config
export default defineConfig({
  site: 'https://excloudvault.mbabros.com',
  integrations: [
    starlight({
      title: 'ExCloudVault.com',
      description: 'Showcase and Knowledge Base for building an enterprise-grade self-hosted private cloud with ExCloudVault.com.',
      social: [
        { icon: 'github', label: 'GitHub', href: 'https://github.com/mbabros/homelab' },
      ],
      editLink: {
        baseUrl: 'https://github.com/mbabros/mbabros.github.io/edit/main/',
      },
      plugins: [
        starlightBlog({
          title: 'Engineering Blog',
          authors: {
            excloudvault: {
              name: 'ExCloudVault Team',
              title: 'Private Cloud Architects',
            },
            mbabros: {
              name: 'ExCloudVault Team',
              title: 'Private Cloud Architects',
            },
          },
        }),
      ],
      sidebar: [
        {
          label: 'Homelab Showcase',
          items: [
            { label: 'Overview & Architecture', slug: 'showcase/architecture' },
            { label: 'Service Inventory & Port Map', slug: 'showcase/services' },
          ],
        },
        {
          label: 'Private Cloud Blueprints',
          items: [
            { label: '1. OCI Ingress & Caddy SSL', slug: 'guides/oci-caddy' },
            { label: '2. Zero-Port Tailscale Mesh', slug: 'guides/tailscale-mesh' },
            { label: '3. Host Firewall & HTTP/3 QUIC', slug: 'guides/firewall-hardening' },
            { label: '4. Apple Silicon PaaS (OrbStack & Coolify)', slug: 'guides/coolify-paas' },
            { label: '5. Codified Application Stacks', slug: 'guides/app-stacks' },
          ],
        },
        {
          label: 'Customer Support & Ops',
          items: [
            { label: 'Troubleshooting Runbooks', slug: 'support/troubleshooting' },
            { label: 'Frequently Asked Questions', slug: 'support/faq' },
          ],
        },
      ],
    }),
  ],
});
