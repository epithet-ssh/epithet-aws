#!/bin/bash
set -euo pipefail

# CA Lambda Launcher Script
# Writes CA private key from environment variable and starts epithet ca

# Required environment variables:
#   CA_PRIVATE_KEY - CA private key (passed from Secrets Manager via env var)
#   POLICY_URL     - URL of the policy server

# Validate required environment variables
: "${CA_PRIVATE_KEY:?CA_PRIVATE_KEY environment variable is required}"
: "${POLICY_URL:?POLICY_URL environment variable is required}"

# Set defaults
PORT="${AWS_LWA_PORT:-8080}"
KEY_FILE="/tmp/ca.key"

# Write CA private key to file
echo "Writing CA private key to ${KEY_FILE}..." >&2
printf '%s\n' "${CA_PRIVATE_KEY}" > "${KEY_FILE}"
chmod 600 "${KEY_FILE}"

echo "Starting epithet CA server on port ${PORT}..." >&2

# Start the epithet CA server
exec /var/task/epithet ca \
    --listen "0.0.0.0:${PORT}" \
    --key "${KEY_FILE}" \
    --policy "${POLICY_URL}"
