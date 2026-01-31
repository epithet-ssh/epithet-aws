# AWS AppConfig resources for dynamic policy source
# The AppConfig Lambda extension serves config on localhost:2772

# AppConfig application
resource "aws_appconfig_application" "policy" {
  name        = "${local.name_prefix}-policy"
  description = "Policy configuration for ${local.name_prefix}"
  tags        = local.common_tags
}

# AppConfig environment
resource "aws_appconfig_environment" "policy" {
  application_id = aws_appconfig_application.policy.id
  name           = "production"
  description    = "Production policy environment"
  tags           = local.common_tags
}

# Configuration profile (hosted store)
resource "aws_appconfig_configuration_profile" "policy" {
  application_id = aws_appconfig_application.policy.id
  name           = "policy"
  location_uri   = "hosted"
  description    = "Policy source configuration"
  tags           = local.common_tags
}

# Configuration version from policy-source.cue
resource "aws_appconfig_hosted_configuration_version" "policy" {
  application_id           = aws_appconfig_application.policy.id
  configuration_profile_id = aws_appconfig_configuration_profile.policy.configuration_profile_id
  content_type             = "text/plain" # CUE doesn't have a registered MIME type
  content                  = file("${path.module}/../config/policy-source.cue")
  description              = "Policy source"
}

# Deploy configuration (uses predefined AllAtOnce strategy for immediate deployment)
resource "aws_appconfig_deployment" "policy" {
  application_id           = aws_appconfig_application.policy.id
  environment_id           = aws_appconfig_environment.policy.environment_id
  configuration_profile_id = aws_appconfig_configuration_profile.policy.configuration_profile_id
  configuration_version    = aws_appconfig_hosted_configuration_version.policy.version_number
  deployment_strategy_id   = "AppConfig.AllAtOnce"
  description              = "Policy deployment"
  tags                     = local.common_tags
}
