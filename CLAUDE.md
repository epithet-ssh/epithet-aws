# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

epithet-aws is a **template repository** for deploying the epithet SSH certificate authority on AWS Lambda. Users clone or fork this repository to create their own CA and policy server deployments.

The core CA and policy logic lives in `github.com/epithet-ssh/epithet`. This repository provides:

1. AWS Lambda handlers (`cmd/epithet-aws/`)
2. S3 certificate archival (`pkg/s3archiver/`)
3. Terraform/OpenTofu deployment (`terraform/`)

## Architecture

This is a deployment template that wraps the main epithet library. Users are expected to:

- Fork/clone this repository
- Configure their policy in `config/policy/policy.yaml`
- Optionally customize the Go code for their needs
- Deploy using the provided Terraform/Make commands

The epithet dependency is specified as a version tag in go.mod (e.g., `v0.1.0`). Users can update to newer versions with `go get github.com/epithet-ssh/epithet@vX.Y.Z`.

## Build Commands

```bash
# Build local binary for testing
make build

# Build Lambda deployment packages (linux/arm64)
make build-lambda

# Run tests
make test
```

The Lambda build creates two zip files in `bin/`:
- `bootstrap-ca.zip` - CA Lambda function (contains only the binary)
- `bootstrap-policy.zip` - Policy Lambda function (contains binary and all files from `config/policy/`)

Both zips contain the same `bootstrap` binary - the Lambda handlers use the `EPITHET_CMD` environment variable to determine which subcommand to run (`ca` or `policy`). The policy Lambda zip also includes all configuration files from `config/policy/`.

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

## Lambda Handler Architecture

The binary at `cmd/epithet-aws/main.go` is the Lambda entry point. It uses Kong CLI parsing with two subcommands:

1. **`epithet-aws ca`** (cmd/epithet-aws/aws.go:AwsCALambdaCLI)
   - Loads CA private key from AWS Secrets Manager (`CA_SECRET_ARN`)
   - Calls policy server at `POLICY_URL` for authorization decisions
   - Archives certificates to S3 (`CERT_ARCHIVE_BUCKET`, optional)
   - All configuration via environment variables (set by Terraform)
   - Wraps `github.com/epithet-ssh/epithet/pkg/caserver.New()`

2. **`epithet-aws policy`** (cmd/epithet-aws/aws.go:AwsPolicyLambdaCLI)
   - Loads policy config from bundled file (`/var/task/policy.yaml`)
   - Loads CA public key from SSM Parameter Store (`CA_PUBLIC_KEY_PARAM`)
   - Validates OIDC tokens and evaluates authorization rules
   - Wraps `github.com/epithet-ssh/epithet/pkg/policyserver.NewHandler()`

Both handlers use `handleLambdaRequest()` to convert API Gateway v2 HTTP events to standard Go `http.Handler` interface.

## S3 Certificate Archiver

`pkg/s3archiver/s3archiver.go` provides async buffered certificate archival:

- **Date partitioning**: `year=YYYY/month=MM/day=DD/serial-NNNN.json`
- **Async writes**: Buffered channel (default 100 events) with background goroutine
- **Best-effort**: Logs errors but never fails certificate issuance
- **Graceful shutdown**: Drains pending events on Lambda termination

The archiver is wired to the CA Lambda via `certLoggerAdapter` which implements the epithet `caserver.CertLogger` interface.

## Terraform Structure

- `main.tf` - Common tags and name prefixes
- `ca.tf` - CA Lambda, API Gateway, S3 bucket, IAM roles
- `policy.tf` - Policy Lambda, API Gateway, IAM roles
- `secrets.tf` - Secrets Manager secret for CA private key, SSM parameter for CA public key
- `variables.tf` - Input variables (project name, region, retention settings)
- `outputs.tf` - CA URL, policy URL, bucket name, CA public key

**Key Terraform resources**:
- API Gateway v2 HTTP APIs (not REST APIs)
- Lambda functions using `provided.al2023` runtime (custom Go binary)
- ARM64 architecture for cost savings
- Secrets Manager for CA private key
- SSM Parameter Store for CA public key

## Environment Variables

### CA Lambda
- `CA_SECRET_ARN` - Secrets Manager ARN for CA private key (raw OpenSSH private key format)
- `POLICY_URL` - Internal policy Lambda endpoint
- `CERT_ARCHIVE_BUCKET` - S3 bucket name
- `CERT_ARCHIVE_PREFIX` - S3 key prefix (default: "certs")
- `EPITHET_CMD` - Set to "ca" by Terraform

### Policy Lambda
- `CA_PUBLIC_KEY_PARAM` - SSM parameter name containing CA public key
- `EPITHET_CMD` - Set to "policy" by Terraform

### TLS Configuration (both handlers)
- `EPITHET_INSECURE` - Disable TLS certificate verification (NOT RECOMMENDED for production)
- `EPITHET_TLS_CA_CERT` - Path to PEM file with trusted CA certificates

TLS configuration can also be set via command-line flags:
- `--insecure` - Disable TLS certificate verification
- `--tls-ca-cert` - Path to PEM file with trusted CA certificates

Policy configuration is loaded from `/var/task/policy.yaml` (bundled in the Lambda zip). The CA public key is loaded from SSM Parameter Store at runtime.

## Testing Locally

The binary can run outside Lambda for testing:
```bash
go build ./cmd/epithet-aws

# Test CA subcommand (requires AWS credentials)
export CA_SECRET_ARN=arn:aws:secretsmanager:...
export POLICY_URL=https://...
./epithet-aws ca

# Test policy subcommand (requires policy.yaml at /var/task/policy.yaml)
# For local testing, you may need to create this path or modify the code
./epithet-aws policy
```

In Lambda, the `EPITHET_CMD` env var auto-populates `os.Args` to select the subcommand.

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

# No code deployment needed - Lambdas read from Secrets Manager/SSM
```

### Retrieve CA public key
```bash
# Using AWS CLI
aws ssm get-parameter --name $(tofu -chdir=terraform output -raw ca_public_key_parameter) --query Parameter.Value --output text --region $(tofu -chdir=terraform output -raw region)

# Or directly from Terraform output (after tofu refresh)
tofu -chdir=terraform output ca_public_key
```

### Update epithet dependency
```bash
# Update to a new version
go get github.com/epithet-ssh/epithet@v0.2.0
go mod tidy

# Rebuild and deploy
make build-lambda
make apply
```

### Add S3 archival to existing deployment
S3 archival is enabled by default. The S3 bucket is created by Terraform in ca.tf and the `CERT_ARCHIVE_BUCKET` environment variable is automatically set.

### Local development with epithet changes
If developing changes to both epithet and epithet-aws:

```bash
# Clone epithet as sibling directory
git clone https://github.com/epithet-ssh/epithet.git ../epithet

# Add replace directive temporarily
echo 'replace github.com/epithet-ssh/epithet => ../epithet' >> go.mod

# Build and test
make build

# Remove replace before committing
```

## Customization Points

Users commonly customize:

1. **Policy rules** - `config/policy/policy.yaml`
2. **Terraform variables** - region, project name, retention
3. **Certificate extensions** - `cmd/epithet-aws/aws.go`
4. **Logging destinations** - extend `pkg/s3archiver/`
5. **Authentication methods** - modify policy handler

## Cost Estimate

Typical personal use (few connections per day):
- API Gateway: ~$0.05/month
- Lambda (free tier): ~$0.10/month
- Secrets Manager: ~$0.40/month
- S3 storage: ~$0.01/month
- **Total: < $1/month**

## Deployment Dependencies

Required tools:
- Go 1.25+
- OpenTofu or Terraform
- AWS CLI with configured credentials
- Make

AWS resources created:
- 2 Lambda functions (CA + Policy)
- 2 API Gateway HTTP APIs
- 1 Secrets Manager secret (CA private key)
- 1 SSM parameter (CA public key)
- 1 S3 bucket (cert archive)
- IAM roles and policies
- CloudWatch log groups

## Secret Storage

The CA key pair is stored separately for security:
- **Private key**: Secrets Manager - raw OpenSSH private key format (e.g., `-----BEGIN OPENSSH PRIVATE KEY-----...`)
- **Public key**: SSM Parameter Store - standard SSH public key format (e.g., `ssh-ed25519 AAAA...`)

This separation ensures the policy Lambda (which only needs the public key) cannot access the private key.

Run `make setup-ca-key` after initial deployment to generate and upload both keys.
