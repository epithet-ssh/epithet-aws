#!/bin/bash
set -euo pipefail

# Policy Lambda Launcher Script
# Uses CA public key from environment variable and starts epithet policy

# Required environment variables:
#   CA_PUBLIC_KEY         - CA public key (passed from SSM via env var)
#   DISCOVERY_BASE_URL    - Base URL for discovery links (CloudFront CDN)
#   APPCONFIG_APPLICATION - AppConfig application name
#   APPCONFIG_ENVIRONMENT - AppConfig environment name
#   APPCONFIG_CONFIGURATION - AppConfig configuration profile name

# Validate required environment variables
: "${CA_PUBLIC_KEY:?CA_PUBLIC_KEY environment variable is required}"
: "${DISCOVERY_BASE_URL:?DISCOVERY_BASE_URL environment variable is required}"
: "${APPCONFIG_APPLICATION:?APPCONFIG_APPLICATION environment variable is required}"
: "${APPCONFIG_ENVIRONMENT:?APPCONFIG_ENVIRONMENT environment variable is required}"
: "${APPCONFIG_CONFIGURATION:?APPCONFIG_CONFIGURATION environment variable is required}"

# Set defaults
PORT="${AWS_LWA_PORT:-8080}"

# Validate key is set (not the placeholder)
if [ "${CA_PUBLIC_KEY}" = "placeholder - run make setup-ca-key to populate" ]; then
    echo "ERROR: CA public key not set - run 'make setup-ca-key' first" >&2
    exit 1
fi

# Build AppConfig URL for policy-source
# The AppConfig Lambda extension serves config on localhost:2772
POLICY_SOURCE_URL="http://localhost:2772/applications/${APPCONFIG_APPLICATION}/environments/${APPCONFIG_ENVIRONMENT}/configurations/${APPCONFIG_CONFIGURATION}"

echo "Starting epithet policy server on port ${PORT}..." >&2

# Start the epithet policy server
# Config files are bundled in /var/task/ (policy.yaml, policy.cue, etc.)
# Policy source is loaded from AppConfig via the Lambda extension
exec /var/task/epithet policy \
    --config '/var/task/*.{yaml,yml,cue,json}' \
    --policy-source "${POLICY_SOURCE_URL}" \
    --listen "0.0.0.0:${PORT}" \
    --ca-pubkey "${CA_PUBLIC_KEY}" \
    --discovery-base-url "${DISCOVERY_BASE_URL}"
