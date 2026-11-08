#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
SSH_USER="${SSH_USER:-$USER}"
SSH_DIR="$DIR/data/ssh/keys"
KEY_FILE="$SSH_DIR/id.${SSH_USER}@host.docker.internal"

mkdir -p "$SSH_DIR"

if [ ! -f "$KEY_FILE" ]; then
    echo "==> Generating dedicated SSH key for Coolify..."
    ssh-keygen -t ed25519 -a 100 -f "$KEY_FILE" -q -N "" -C "coolify-orbstack"
    chmod 600 "$KEY_FILE"
    chmod 644 "$KEY_FILE.pub"
    echo "==> Key generated at $KEY_FILE"
else
    echo "==> Coolify SSH key already exists at $KEY_FILE"
fi

# Ensure ~/.ssh/authorized_keys exists
mkdir -p ~/.ssh
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

# Check if public key is already in authorized_keys
if ! grep -q "coolify-orbstack" ~/.ssh/authorized_keys; then
    echo "==> Appending Coolify public key to ~/.ssh/authorized_keys..."
    cat "$KEY_FILE.pub" >> ~/.ssh/authorized_keys
    echo "==> Key authorized successfully."
else
    echo "==> Coolify public key already authorized in ~/.ssh/authorized_keys."
fi

echo "==> Testing local SSH authentication..."
if ssh -i "$KEY_FILE" -o BatchMode=yes -o StrictHostKeyChecking=accept-new ${SSH_USER}@localhost "echo SSH connection test successful" 2>/dev/null; then
    echo "✅ SSH connection verified! Coolify can connect to macOS host via ${SSH_USER}@host.docker.internal."
else
    echo "⚠️ Local SSH test didn't complete automatically. Please ensure 'Remote Login' is enabled in macOS System Settings > General > Sharing."
fi
