#!/bin/bash
set -euo pipefail

# Policy Lambda Launcher Script
# Uses CA public key from environment variable and starts epithet policy

# Required environment variables:
#   CA_PUBLIC_KEY      - CA public key (passed from SSM via env var)
#   DISCOVERY_BASE_URL - Base URL for discovery links (CloudFront CDN)

# Validate required environment variables
: "${CA_PUBLIC_KEY:?CA_PUBLIC_KEY environment variable is required}"
: "${DISCOVERY_BASE_URL:?DISCOVERY_BASE_URL environment variable is required}"

# Set defaults
PORT="${AWS_LWA_PORT:-8080}"

# Validate key is set (not the placeholder)
if [ "${CA_PUBLIC_KEY}" = "placeholder - run make setup-ca-key to populate" ]; then
    echo "ERROR: CA public key not set - run 'make setup-ca-key' first" >&2
    exit 1
fi

echo "Starting epithet policy server on port ${PORT}..." >&2

# Start the epithet policy server
# Config files are bundled in /var/task/ (policy.yaml, policy.cue, etc.)
exec /var/task/epithet policy \
    --config '/var/task/*.{yaml,yml,cue,json}' \
    --listen "0.0.0.0:${PORT}" \
    --ca-pubkey "${CA_PUBLIC_KEY}" \
    --discovery-base-url "${DISCOVERY_BASE_URL}"
