# epithet-aws

AWS Lambda deployment template for [epithet](https://github.com/epithet-ssh/epithet) SSH certificate authority and policy server.

**Use this template** to deploy your own epithet CA and policy servers on AWS Lambda with API Gateway, Secrets Manager, and SSM Parameter Store.

## Getting Started

### 1. Create Your Repository

Clone or fork this repository to create your own deployment:

```bash
git clone https://github.com/epithet-ssh/epithet-aws.git my-ssh-ca
cd my-ssh-ca
```

Make this a *private* repo as you will have things like your OIDC info in the config file.

### 2. Prerequisites

- [OpenTofu](https://opentofu.org/) or Terraform
- AWS CLI configured with credentials
- curl, zip, make

### 3. Configure Your Policy

Edit `config/policy/policy.yaml` to configure your OIDC provider and authorization rules:

```yaml
policy:
  oidc_issuer: https://accounts.google.com
  oidc_audience: your-oauth-client-id.apps.googleusercontent.com

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
├── config/
│   └── policy/          # Policy configuration (bundled in Lambda)
│       ├── policy.yaml
├── scripts/
│   ├── ca-launcher.sh       # CA Lambda startup script
│   ├── policy-launcher.sh   # Policy Lambda startup script
│   └── generate-ca-key.sh   # CA key generation
├── terraform/           # OpenTofu/Terraform deployment
│   ├── main.tf          # Provider, common config, Lambda layer
│   ├── ca.tf            # CA Lambda, API Gateway
│   ├── policy.tf        # Policy Lambda, API Gateway
│   ├── secrets.tf       # Secrets Manager, SSM Parameter
│   ├── variables.tf     # Input variables
│   └── outputs.tf       # Output values
└── Makefile
```

## Make Commands

| Command | Description |
|---------|-------------|
| `make build-lambda` | Download epithet binary and build Lambda packages |
| `make download-binary` | Just download the epithet binary |
| `make test` | Validate launcher scripts |
| `make init` | Initialize Terraform |
| `make plan` | Build Lambda and run Terraform plan |
| `make apply` | Build and deploy to AWS |
| `make setup-ca-key` | Generate and upload CA key pair |
| `make destroy` | Tear down all AWS resources |
| `make clean` | Remove build artifacts |

## Architecture

This deployment uses the [AWS Lambda Web Adapter](https://github.com/awslabs/aws-lambda-web-adapter) to run the epithet binary directly in Lambda.

```
Client (epithet agent)
    ↓
API Gateway (HTTPS)
    ↓
Lambda Web Adapter
    ↓
epithet binary (CA or Policy)
```

### CA Lambda

- Runs `epithet ca` to sign SSH certificates
- CA private key passed via `CA_PRIVATE_KEY` environment variable (from Secrets Manager)
- Calls policy server for authorization decisions

**Environment variables** (set by Terraform):
- `CA_PRIVATE_KEY`: CA private key (from Secrets Manager)
- `POLICY_URL`: Internal URL of policy Lambda
- `AWS_LWA_PORT`: HTTP port for Lambda Web Adapter (8080)

### Policy Lambda

- Runs `epithet policy` to evaluate authorization
- Validates OIDC tokens from users
- Evaluates rules from bundled config files
- CA public key passed via `CA_PUBLIC_KEY` environment variable (from SSM)

**Environment variables** (set by Terraform):
- `CA_PUBLIC_KEY`: CA public key (from SSM Parameter Store)
- `AWS_LWA_PORT`: HTTP port for Lambda Web Adapter (8080)

## Updating Policy Configuration

Edit files in `config/policy/` and redeploy:

```bash
vim config/policy/policy.yaml
make apply
```

Policy files (`.yaml`, `.yml`, `.cue`, `.json`) are bundled into the Lambda zip, so redeployment is required for changes to take effect.

## Cost Estimate

With typical personal use (a few connections per day):

| Service | Monthly Cost |
|---------|-------------|
| API Gateway | ~$0.05 |
| Lambda | ~$0.10 |
| Secrets Manager | ~$0.40 |
| SSM Parameter | Free |
| **Total** | **< $0.60** |

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

Edit `EPITHET_VERSION` in the Makefile:

```makefile
EPITHET_VERSION := v0.3.3
```

Then rebuild and deploy:

```bash
make clean
make apply
```

## Troubleshooting

### Check Lambda Logs

```bash
# CA Lambda
aws logs tail /aws/lambda/$(tofu -chdir=terraform output -raw ca_function_name) \
  --since 10m --region $(tofu -chdir=terraform output -raw region)

# Policy Lambda
aws logs tail /aws/lambda/$(tofu -chdir=terraform output -raw policy_function_name) \
  --since 10m --region $(tofu -chdir=terraform output -raw region)
```

### Common Issues

- **"CA public key not set"**: Run `make setup-ca-key` after initial deployment
- **500 errors**: Check Lambda logs for detailed error messages
- **Cold start timeouts**: Increase `lambda_timeout_sec` in Terraform variables

## License

Same as [epithet](https://github.com/epithet-ssh/epithet) - see LICENSE in main repository.

## Releases

Version updates are coordinated via the [packaging](https://github.com/epithet-ssh/packaging) repository, which orchestrates unified releases across all epithet-ssh projects.

## Related Projects

- [epithet](https://github.com/epithet-ssh/epithet) - Core SSH CA implementation
