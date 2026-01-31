output "ca_url" {
  description = "CA server API endpoint URL"
  value       = "${aws_apigatewayv2_api.ca.api_endpoint}/"
}

output "policy_url" {
  description = "Policy server API endpoint URL (internal use)"
  value       = aws_apigatewayv2_api.policy.api_endpoint
}

output "ca_secret_name" {
  description = "Name of the Secrets Manager secret containing the CA key"
  value       = aws_secretsmanager_secret.ca_key.name
}

output "ca_secret_arn" {
  description = "ARN of the Secrets Manager secret containing the CA key"
  value       = aws_secretsmanager_secret.ca_key.arn
}

output "ca_public_key_parameter" {
  description = "Name of the SSM parameter containing the CA public key"
  value       = aws_ssm_parameter.ca_public_key.name
}

output "ca_public_key_command" {
  description = "Command to retrieve the CA public key"
  value       = "aws ssm get-parameter --name ${aws_ssm_parameter.ca_public_key.name} --query Parameter.Value --output text"
}

output "ca_public_key" {
  description = "CA public key (run 'make setup-ca-key' first to populate)"
  value       = aws_ssm_parameter.ca_public_key.value
  sensitive   = true
}

output "region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "discovery_url" {
  description = "CloudFront URL for discovery endpoint (cached)"
  value       = "https://${aws_cloudfront_distribution.discovery.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID (for cache invalidation)"
  value       = aws_cloudfront_distribution.discovery.id
}

output "appconfig_application" {
  description = "AppConfig application name for policy source"
  value       = aws_appconfig_application.policy.name
}

output "appconfig_environment" {
  description = "AppConfig environment name for policy source"
  value       = aws_appconfig_environment.policy.name
}

output "appconfig_configuration_profile" {
  description = "AppConfig configuration profile name for policy source"
  value       = aws_appconfig_configuration_profile.policy.name
}
