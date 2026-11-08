# Multi-stage Dockerfile for mbabros.com
# Stage 1: Build Vite / React Frontend from mbabros/mbabros
FROM node:22-alpine AS builder

WORKDIR /app

RUN corepack enable && corepack prepare pnpm@9.15.4 --activate
RUN apk add --no-cache git

ARG GIT_TOKEN=""

RUN if [ -n "$GIT_TOKEN" ]; then \
        git clone --depth 1 https://${GIT_TOKEN}@github.com/mbabros/mbabros.git .; \
    else \
        git clone --depth 1 https://github.com/mbabros/mbabros.git .; \
    fi

RUN pnpm config set ignore-scripts false && pnpm install --no-frozen-lockfile
RUN pnpm --dir artifacts/cloud-consulting run build

# Stage 2: Minimal Production Runner
FROM node:22-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV PORT=3000

# Install SendGrid mail dependency for contact form API
RUN npm init -y && npm install @sendgrid/mail

COPY --from=builder /app/artifacts/cloud-consulting/dist ./dist
COPY server.js ./server.js

EXPOSE 3000

HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://127.0.0.1:3000/healthz || exit 1

CMD ["node", "server.js"]
