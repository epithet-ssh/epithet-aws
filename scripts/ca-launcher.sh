#!/bin/bash
set -euo pipefail

# CA Lambda Launcher Script
# Fetches CA private key from Secrets Manager and starts epithet ca

# Required environment variables:
#   CA_SECRET_ARN - ARN of the Secrets Manager secret containing CA private key
#   POLICY_URL    - URL of the policy server

# Validate required environment variables
: "${CA_SECRET_ARN:?CA_SECRET_ARN environment variable is required}"
: "${POLICY_URL:?POLICY_URL environment variable is required}"

# Set defaults
PORT="${AWS_LWA_PORT:-8080}"
KEY_FILE="/tmp/ca.key"

# Fetch CA private key from Secrets Manager
echo "Fetching CA private key from Secrets Manager..." >&2

aws secretsmanager get-secret-value \
    --secret-id "${CA_SECRET_ARN}" \
    --query 'SecretString' \
    --output text > "${KEY_FILE}"

# Secure the key file
chmod 600 "${KEY_FILE}"

echo "Starting epithet CA server on port ${PORT}..." >&2

# Start the epithet CA server
exec /var/task/epithet ca \
    --listen "0.0.0.0:${PORT}" \
    --key "${KEY_FILE}" \
    --policy "${POLICY_URL}"
