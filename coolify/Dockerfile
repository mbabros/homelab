# Custom Coolify Image for macOS OrbStack Docker Engine
# Base: Official Coolify production image
FROM ghcr.io/coollabsio/coolify:latest

USER root

# Install docker-cli, openssh-client, and networking utilities for local host orchestration
RUN apk update && apk add --no-cache \
    docker-cli \
    docker-cli-compose \
    openssh-client \
    netcat-openbsd \
    curl \
    bash \
    sudo

# Configure SSH client specifically for connecting to macOS host via OrbStack
# Automatically trusts host.docker.internal and configures keepalives
RUN mkdir -p /etc/ssh/ssh_config.d && \
    printf "Host host.docker.internal localhost 127.0.0.1\n    StrictHostKeyChecking no\n    UserKnownHostsFile /dev/null\n    ServerAliveInterval 30\n    ServerAliveCountMax 3\n" > /etc/ssh/ssh_config.d/coolify-orbstack.conf

# Patch Server.php so Coolify treats macOS host as root-equivalent (no sudo required)
RUN php -r ' \
    $file = "/var/www/html/app/Models/Server.php"; \
    $content = file_get_contents($file); \
    $target = "public function isNonRoot()\n    {"; \
    $replace = "public function isNonRoot()\n    {\n        if (in_array(\$this->ip, [\"host.docker.internal\", \"127.0.0.1\", \"localhost\"])) return false;"; \
    $content = str_replace($target, $replace, $content); \
    file_put_contents($file, $content); \
' && php -l /var/www/html/app/Models/Server.php

# Patch shared.php so base_configuration_dir respects BASE_CONFIG_PATH env var
RUN php -r ' \
    $file = "/var/www/html/bootstrap/helpers/shared.php"; \
    $content = file_get_contents($file); \
    $target = "function base_configuration_dir(): string\n{\n    return '\''/data/coolify'\'';"; \
    $replace = "function base_configuration_dir(): string\n{\n    return env('\''BASE_CONFIG_PATH'\'', '\''/data/coolify'\'');"; \
    $content = str_replace($target, $replace, $content); \
    file_put_contents($file, $content); \
' && php -l /var/www/html/bootstrap/helpers/shared.php

# Create standard /data/coolify directories with proper permissions for UID 9999
RUN mkdir -p /data/coolify/source \
             /data/coolify/ssh/keys \
             /data/coolify/ssh/mux \
             /data/coolify/applications \
             /data/coolify/databases \
             /data/coolify/services \
             /data/coolify/backups \
             /data/coolify/proxy \
             /data/coolify/images && \
    chown -R 9999:root /data/coolify 2>/dev/null || true

# Switch back to non-root container user
USER 9999
