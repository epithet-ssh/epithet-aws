#!/bin/bash
set -euo pipefail

# Generate CA key and upload to AWS Secrets Manager
# This script reads the secret name from OpenTofu outputs

# Check for required tools
if ! command -v tofu &> /dev/null; then
    echo "Error: OpenTofu not found. Install with: brew install opentofu"
    exit 1
fi

if ! command -v aws &> /dev/null; then
    echo "Error: AWS CLI not found. Install with: brew install awscli"
    exit 1
fi

if ! command -v ssh-keygen &> /dev/null; then
    echo "Error: ssh-keygen not found"
    exit 1
fi

# Get the secret name and SSM parameter from OpenTofu output
echo "Getting resource names from OpenTofu..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

SECRET_NAME=$(tofu -chdir="$TERRAFORM_DIR" output -raw ca_secret_name)
SSM_PARAM_NAME=$(tofu -chdir="$TERRAFORM_DIR" output -raw ca_public_key_parameter)
REGION=$(tofu -chdir="$TERRAFORM_DIR" output -raw region)

if [ -z "$SECRET_NAME" ]; then
    echo "Error: Could not get secret name from OpenTofu output"
    echo "Make sure you've run 'tofu apply' first"
    exit 1
fi

if [ -z "$SSM_PARAM_NAME" ]; then
    echo "Error: Could not get SSM parameter name from OpenTofu output"
    echo "Make sure you've run 'tofu apply' first"
    exit 1
fi

echo "Generating Ed25519 key pair..."
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Generate Ed25519 key
ssh-keygen -t ed25519 -f "$TEMP_DIR/ca_key" -N "" -C "epithet-ca" >/dev/null 2>&1

# Read private and public keys
PRIVATE_KEY=$(cat "$TEMP_DIR/ca_key")
PUBLIC_KEY=$(cat "$TEMP_DIR/ca_key.pub")

echo "Uploading private key to AWS Secrets Manager..."
aws secretsmanager put-secret-value \
    --region "$REGION" \
    --secret-id "$SECRET_NAME" \
    --secret-string "$PRIVATE_KEY" \
    >/dev/null

echo "Uploading public key to AWS SSM Parameter Store..."
aws ssm put-parameter \
    --region "$REGION" \
    --name "$SSM_PARAM_NAME" \
    --value "$PUBLIC_KEY" \
    --type String \
    --overwrite \
    >/dev/null

echo ""
echo "✓ CA key generated and uploaded successfully"
echo ""
echo "CA Public Key:"
echo "$PUBLIC_KEY"
echo ""
echo "You can retrieve the public key anytime with:"
echo "  aws ssm get-parameter --region $REGION --name $SSM_PARAM_NAME --query Parameter.Value --output text"
