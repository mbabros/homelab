#!/bin/bash
# ============================================================
# GitHub Actions Self-Hosted Runner Setup for Mac Mini
# Installs and registers the runner daemon for mbabros/homelab
# ============================================================
set -e

RUNNER_DIR="$HOME/actions-runner"
REPO_URL="https://github.com/mbabros/homelab"
RUNNER_VERSION="2.338.2"
RUNNER_TAR="actions-runner-osx-arm64-${RUNNER_VERSION}.tar.gz"
DOWNLOAD_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TAR}"
PAT_FILE="$HOME/.passwords/mbabros-github.pat"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; RESET='\033[0m'
info() { echo -e "${GREEN}==>${RESET} $1"; }
warn() { echo -e "${YELLOW}⚠️  $1${RESET}"; }
error() { echo -e "${RED}✗  $1${RESET}"; exit 1; }

[ -f "$PAT_FILE" ] || error "GitHub PAT file not found at $PAT_FILE"

info "Requesting runner registration token from GitHub API..."
REG_TOKEN=$(python3 -c "
import urllib.request, json
pat = open('$PAT_FILE').read().strip()
req = urllib.request.Request('https://api.github.com/repos/mbabros/homelab/actions/runners/registration-token', method='POST', headers={
    'Authorization': f'token {pat}',
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'SetupScript'
})
with urllib.request.urlopen(req) as resp:
    print(json.loads(resp.read().decode())['token'])
")

[ -n "$REG_TOKEN" ] || error "Failed to obtain runner registration token."
info "Registration token obtained successfully."

mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [ ! -f "config.sh" ]; then
    info "Downloading GitHub runner package v${RUNNER_VERSION} for Apple Silicon (ARM64)..."
    curl -fsSL -o "$RUNNER_TAR" "$DOWNLOAD_URL"
    info "Unpacking runner package..."
    tar xzf "$RUNNER_TAR"
    rm -f "$RUNNER_TAR"
fi

# Stop existing service if running
if [ -f ".service" ]; then
    info "Stopping existing runner service..."
    ./svc.sh stop || true
    ./svc.sh uninstall || true
fi

info "Configuring runner for $REPO_URL..."
./config.sh --url "$REPO_URL" \
            --token "$REG_TOKEN" \
            --name "mac-mini-homelab" \
            --labels "macmini,homelab,apple-silicon" \
            --unattended \
            --replace

info "Installing runner as macOS background LaunchAgent service..."
./svc.sh install

info "Starting runner service..."
./svc.sh start

info "Checking runner service status..."
./svc.sh status

echo ""
info "✅ GitHub Actions self-hosted runner is online and registered to $REPO_URL!"
