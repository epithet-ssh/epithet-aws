# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

epithet-aws is a **template repository** for deploying the epithet SSH certificate authority on AWS Lambda. Users clone or fork this repository to create their own CA and policy server deployments.

This repository provides:

1. Shell launcher scripts (`scripts/`)
2. Terraform/OpenTofu deployment (`terraform/`)
3. Policy configuration (`config/policy/`)

The core CA and policy logic comes from the pre-built `epithet` binary (v0.5.0) downloaded from GitHub releases.

## Architecture

This deployment uses the [AWS Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter) to run the epithet binary directly in Lambda without custom wrapper code.

Users are expected to:

- Fork/clone this repository
- Configure their policy in `config/policy/policy.yaml`
- Deploy using the provided Terraform/Make commands

### How It Works

1. Lambda Web Adapter (AWS-provided layer) handles API Gateway events
2. Shell launcher scripts fetch secrets and start the epithet binary
3. epithet runs as an HTTP server on port 8080
4. Lambda Web Adapter proxies requests to the epithet server

## Build Commands

```bash
# Download epithet binary and build Lambda packages
make build-lambda

# Just download the binary
make download-binary

# Validate launcher scripts
make test

# Clean build artifacts
make clean
```

The Lambda build creates two zip files in `bin/`:
- `ca.zip` - CA Lambda function (epithet binary + ca-launcher.sh)
- `policy.zip` - Policy Lambda function (epithet binary + policy-launcher.sh + config/policy/*)

## Deployment Commands

```bash
# Initialize Terraform/OpenTofu
make init

# Plan infrastructure changes (builds Lambda first)
make plan

# Deploy to AWS
make apply

# Generate CA key and upload to AWS
# (private key to Secrets Manager, public key to SSM Parameter Store)
make setup-ca-key

# Destroy infrastructure
make destroy
```

Policy configuration is bundled into the Lambda zip from `config/policy/`. Edit files in this directory and run `make apply` to deploy changes.

## Lambda Architecture

### CA Lambda (`scripts/ca-launcher.sh`)

1. Receives CA private key via environment variable (`CA_PRIVATE_KEY`)
2. Writes key to `/tmp/ca.key` with secure permissions
3. Starts `epithet ca --listen 0.0.0.0:8080 --key /tmp/ca.key --policy $POLICY_URL`

The CA server exposes:
- `GET /` - Returns CA public key with `Link` header pointing to bootstrap endpoint
- `POST /` - Signs certificates (requires Bearer token)

### Policy Lambda (`scripts/policy-launcher.sh`)

1. Receives CA public key via environment variable (`CA_PUBLIC_KEY`)
2. Starts `epithet policy --listen 0.0.0.0:8080 --ca-pubkey "$CA_PUBLIC_KEY" --discovery-base-url "$DISCOVERY_BASE_URL"`
3. Policy config loaded from `/var/task/policy.yaml` (bundled in zip)

The policy server exposes:
- `POST /` - Evaluates policy for certificate requests
- `GET /d/bootstrap` - Redirects to content-addressed bootstrap endpoint (unauthenticated)
- `GET /d/current` - Redirects to content-addressed discovery endpoint (authenticated)
- `GET /d/{hash}` - Serves content-addressed bootstrap/discovery data

Both use the AWS Lambda Web Adapter layer to handle API Gateway integration.

### Discovery Caching (CloudFront)

Discovery endpoints are cached via CloudFront CDN:
- Bootstrap and discovery redirect endpoints: 5-minute cache
- Content-addressed endpoints (`/d/{hash}`): 1-year immutable cache

## Terraform Structure

- `main.tf` - Common tags, name prefixes, Lambda Web Adapter layer ARN
- `ca.tf` - CA Lambda, API Gateway, IAM roles
- `policy.tf` - Policy Lambda, API Gateway, IAM roles
- `cloudfront.tf` - CloudFront distribution for discovery endpoint caching
- `secrets.tf` - Secrets Manager secret for CA private key, SSM parameter for CA public key
- `variables.tf` - Input variables (project name, region, log retention)
- `outputs.tf` - CA URL, policy URL, CA public key

**Key Terraform resources**:
- API Gateway v2 HTTP APIs (not REST APIs)
- Lambda functions using `provided.al2023` runtime with Lambda Web Adapter layer
- ARM64 architecture for cost savings
- Secrets Manager for CA private key
- SSM Parameter Store for CA public key
- CloudFront distribution for discovery endpoint caching

## Environment Variables

### CA Lambda
- `CA_PRIVATE_KEY` - CA private key (from Secrets Manager)
- `POLICY_URL` - Policy Lambda endpoint
- `AWS_LAMBDA_EXEC_WRAPPER` - Set to `/opt/bootstrap` for Lambda Web Adapter
- `AWS_LWA_PORT` - Port for HTTP server (8080)
- `AWS_LWA_READINESS_CHECK_PATH` - Health check path (/)

### Policy Lambda
- `CA_PUBLIC_KEY` - CA public key (from SSM Parameter Store)
- `DISCOVERY_BASE_URL` - CloudFront CDN URL for discovery links
- `AWS_LAMBDA_EXEC_WRAPPER` - Set to `/opt/bootstrap` for Lambda Web Adapter
- `AWS_LWA_PORT` - Port for HTTP server (8080)
- `AWS_LWA_READINESS_CHECK_PATH` - Health check path (/)

## Common Development Tasks

### Update policy configuration
```bash
# Edit policy.yaml
vim config/policy/policy.yaml

# Rebuild and deploy (config is bundled into Lambda zip)
make apply
```

### Rotate CA key
```bash
# Generate new key and upload to AWS
make setup-ca-key

# Redeploy to pick up new key (Lambdas fetch at startup)
make apply
```

### Retrieve CA public key
```bash
# Using AWS CLI
aws ssm get-parameter --name $(tofu -chdir=terraform output -raw ca_public_key_parameter) --query Parameter.Value --output text --region $(tofu -chdir=terraform output -raw region)

# Or directly from Terraform output (after tofu refresh)
tofu -chdir=terraform output ca_public_key
```

### Update epithet version
Edit `EPITHET_VERSION` in the Makefile, then:
```bash
make clean
make build-lambda
make apply
```

## Customization Points

Users commonly customize:

1. **Policy rules** - `config/policy/policy.yaml`
2. **Terraform variables** - region, project name, log retention
3. **Epithet version** - `EPITHET_VERSION` in Makefile

## Cost Estimate

Typical personal use (few connections per day):
- API Gateway: ~$0.05/month
- Lambda (free tier): ~$0.10/month
- Secrets Manager: ~$0.40/month
- **Total: < $0.60/month**

## Deployment Dependencies

Required tools:
- curl (for downloading epithet binary)
- zip
- OpenTofu or Terraform
- AWS CLI with configured credentials
- Make

AWS resources created:
- 2 Lambda functions (CA + Policy)
- 2 API Gateway HTTP APIs
- 1 CloudFront distribution (discovery caching)
- 1 Secrets Manager secret (CA private key)
- 1 SSM parameter (CA public key)
- IAM roles and policies
- CloudWatch log groups

## Secret Storage

The CA key pair is stored separately for security:
- **Private key**: Secrets Manager - raw OpenSSH private key format (e.g., `-----BEGIN OPENSSH PRIVATE KEY-----...`)
- **Public key**: SSM Parameter Store - standard SSH public key format (e.g., `ssh-ed25519 AAAA...`)

This separation ensures the policy Lambda (which only needs the public key) cannot access the private key.

Run `make setup-ca-key` after initial deployment to generate and upload both keys.

## Certificate Audit Trail

Certificate issuance events are logged to CloudWatch Logs. Set `log_retention_days` in Terraform variables to control retention.
