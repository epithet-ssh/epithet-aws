# CA private key stored in Secrets Manager
resource "aws_secretsmanager_secret" "ca_key" {
  name                    = "${local.name_prefix}-ca-key"
  description             = "Epithet CA private key"
  recovery_window_in_days = 0 # Force immediate deletion on destroy

  tags = local.common_tags
}

# CA public key stored in SSM Parameter Store (not a secret, just config)
resource "aws_ssm_parameter" "ca_public_key" {
  name        = "/${local.name_prefix}/ca-public-key"
  description = "Epithet CA public key"
  type        = "String"
  value       = "placeholder - run make setup-ca-key to populate"

  tags = local.common_tags

  lifecycle {
    ignore_changes = [value]
  }
}

# Note: Both values are populated by running `make setup-ca-key` after initial deploy

# Data source to read the current secret value (for passing to Lambda)
data "aws_secretsmanager_secret_version" "ca_key" {
  secret_id = aws_secretsmanager_secret.ca_key.id
}
