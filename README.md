# epithet-aws

AWS Lambda deployment template for [epithet](https://github.com/epithet-ssh/epithet) SSH certificate authority and policy server.

**Use this template** to deploy your own epithet CA and policy servers on AWS Lambda with API Gateway, Secrets Manager, SSM Parameter Store, and S3 certificate archival.

## Getting Started

### 1. Create Your Repository

Clone or fork this repository to create your own deployment:

```bash
git clone https://github.com/epithet-ssh/epithet-aws.git my-ssh-ca
cd my-ssh-ca
```

Make this a *private* repo as you will have things like your OIDC info in the config file.

### 2. Prerequisites

- [Go 1.25+](https://go.dev/dl/)
- [OpenTofu](https://opentofu.org/) or Terraform
- AWS CLI configured with credentials

### 3. Configure Your Policy

Edit `config/policy/policy.yaml` to configure your OIDC provider and authorization rules:

```yaml
# CA public key is loaded from SSM Parameter Store at runtime
# This placeholder satisfies config validation
ca_public_key: "placeholder - loaded from SSM"

oidc:
  issuer: https://accounts.google.com
  audience: your-oauth-client-id.apps.googleusercontent.com

users:
  admin@example.com: [wheel, admin]
  dev@example.com: [dev]

defaults:
  allow:
    root: [wheel]
  expiration: "5m"

hosts:
  "prod-*":
    allow:
      root: [admin]
    expiration: "2m"
```

See `config/policy/policy.example.yaml` for a comprehensive example with all OIDC providers and the [epithet policy documentation](https://github.com/epithet-ssh/epithet/blob/main/docs/policy-server.md) for detailed configuration options.

### 4. Deploy to AWS

```bash
# Optional: customize region and project name in terraform/terraform.tfvars
# aws_region = "us-east-1"
# project_name = "my-ssh-ca"

# Deploy infrastructure
make init
make apply
```

### 5. Generate CA Key

After the infrastructure is deployed, generate and upload your CA key pair:

```bash
make setup-ca-key
```

This creates an Ed25519 key pair and stores:
- Private key in AWS Secrets Manager
- Public key in SSM Parameter Store

### 6. Get Your CA URL and Public Key

```bash
# Get the CA URL for epithet client configuration
tofu -chdir=terraform output ca_url

# Get the CA public key (for sshd TrustedUserCAKeys)
aws ssm get-parameter \
  --name $(tofu -chdir=terraform output -raw ca_public_key_parameter) \
  --query Parameter.Value --output text \
  --region $(tofu -chdir=terraform output -raw region)
```

### 7. Configure SSH Server

On your SSH servers, add the CA public key to trust certificates:

```bash
# Add to /etc/ssh/sshd_config
TrustedUserCAKeys /etc/ssh/ca_key.pub

# Save the CA public key
echo "ssh-ed25519 AAAA..." > /etc/ssh/ca_key.pub

# Reload sshd
service sshd reload  # or: systemctl reload sshd
```

## Project Structure

```
epithet-aws/
├── cmd/epithet-aws/     # Lambda handler binary
│   ├── main.go          # CLI entry point
│   └── aws.go           # CA and policy Lambda handlers
├── config/
│   └── policy/          # Policy configuration (bundled in Lambda)
│       └── policy.yaml
├── pkg/s3archiver/      # S3 certificate archival package
├── terraform/           # OpenTofu/Terraform deployment
│   ├── main.tf          # Provider and common config
│   ├── ca.tf            # CA Lambda, API Gateway, S3
│   ├── policy.tf        # Policy Lambda, API Gateway
│   ├── secrets.tf       # Secrets Manager, SSM Parameter
│   ├── variables.tf     # Input variables
│   └── outputs.tf       # Output values
└── scripts/             # Deployment automation
```

## Make Commands

| Command | Description |
|---------|-------------|
| `make build` | Build local binary for testing |
| `make build-lambda` | Build Lambda deployment packages |
| `make test` | Run Go tests |
| `make init` | Initialize Terraform |
| `make plan` | Build Lambda and run Terraform plan |
| `make apply` | Build and deploy to AWS |
| `make setup-ca-key` | Generate and upload CA key pair |
| `make destroy` | Tear down all AWS resources |

## Architecture

```
Client (epithet agent)
    ↓
API Gateway (HTTPS)
    ↓
CA Lambda ←→ Policy Lambda
    ↓              ↓
Secrets Mgr    SSM Param
(private key)  (public key)
    ↓
S3 (cert archive)
```

### CA Lambda

- Signs SSH certificates based on policy server decisions
- Loads CA private key from AWS Secrets Manager
- Archives certificates to S3

**Environment variables** (set by Terraform):
- `CA_SECRET_ARN`: Secrets Manager ARN for CA private key
- `POLICY_URL`: Internal URL of policy Lambda
- `CERT_ARCHIVE_BUCKET`: S3 bucket for archival
- `CERT_ARCHIVE_PREFIX`: S3 key prefix (default: "certs")
- `EPITHET_CMD`: Set to "ca"

### Policy Lambda

- Validates OIDC tokens from users
- Evaluates authorization rules from bundled config
- Loads CA public key from SSM Parameter Store
- Returns certificate parameters

**Environment variables** (set by Terraform):
- `CA_PUBLIC_KEY_PARAM`: SSM parameter name for CA public key
- `EPITHET_CMD`: Set to "policy"

## Updating Policy Configuration

Edit `config/policy/policy.yaml` and redeploy:

```bash
vim config/policy/policy.yaml
make apply
```

The policy file is bundled into the Lambda zip, so redeployment is required for changes to take effect.

## Cost Estimate

With typical personal use (a few connections per day):

| Service | Monthly Cost |
|---------|-------------|
| API Gateway | ~$0.05 |
| Lambda | ~$0.10 |
| Secrets Manager | ~$0.40 |
| S3 | ~$0.01 |
| SSM Parameter | Free |
| **Total** | **< $1** |

## Customization

This template is designed to be forked and customized.

### Terraform Variables

Create `terraform/terraform.tfvars`:

```hcl
aws_region     = "us-east-1"
project_name   = "my-ssh-ca"
lambda_memory_mb = 256
log_retention_days = 30
```

### Update epithet Version

```bash
go get github.com/epithet-ssh/epithet@v0.2.0
go mod tidy
make apply
```

## Troubleshooting

### Check Lambda Logs

```bash
# CA Lambda
aws logs tail /aws/lambda/$(tofu -chdir=terraform output -raw project_name)-ca \
  --since 10m --region $(tofu -chdir=terraform output -raw region)

# Policy Lambda
aws logs tail /aws/lambda/$(tofu -chdir=terraform output -raw project_name)-policy \
  --since 10m --region $(tofu -chdir=terraform output -raw region)
```

### Common Issues

- **"CA public key not set"**: Run `make setup-ca-key` after initial deployment
- **"ca_public_key is required"**: Ensure policy.yaml has the placeholder `ca_public_key` field
- **500 errors**: Check Lambda logs for detailed error messages

## License

Same as [epithet](https://github.com/epithet-ssh/epithet) - see LICENSE in main repository.

## Related Projects

- [epithet](https://github.com/epithet-ssh/epithet) - Core SSH CA implementation
