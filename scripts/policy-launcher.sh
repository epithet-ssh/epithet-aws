#!/bin/bash
set -euo pipefail

# Policy Lambda Launcher Script
# Fetches CA public key from SSM and starts epithet policy

# Required environment variables:
#   CA_PUBLIC_KEY_PARAM - SSM parameter name containing CA public key

# Validate required environment variables
: "${CA_PUBLIC_KEY_PARAM:?CA_PUBLIC_KEY_PARAM environment variable is required}"

# Set defaults
PORT="${AWS_LWA_PORT:-8080}"

# Fetch CA public key from SSM Parameter Store
echo "Fetching CA public key from SSM Parameter Store..." >&2

CA_PUBLIC_KEY=$(aws ssm get-parameter \
    --name "${CA_PUBLIC_KEY_PARAM}" \
    --query 'Parameter.Value' \
    --output text)

if [ -z "${CA_PUBLIC_KEY}" ] || [ "${CA_PUBLIC_KEY}" = "placeholder - run make setup-ca-key to populate" ]; then
    echo "ERROR: CA public key not set - run 'make setup-ca-key' first" >&2
    exit 1
fi

echo "Starting epithet policy server on port ${PORT}..." >&2

# Start the epithet policy server
# Config files are bundled in /var/task/ (policy.yaml, policy.cue, etc.)
exec /var/task/epithet policy \
    --config '/var/task/*.{yaml,yml,cue,json}' \
    --listen "0.0.0.0:${PORT}" \
    --ca-pubkey "${CA_PUBLIC_KEY}"
