terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  # Uncomment to use S3 backend for state storage
  # backend "s3" {
  #   bucket = "my-terraform-state-bucket"
  #   key    = "epithet/terraform.tfstate"
  #   region = "us-west-2"
  # }
}

provider "aws" {
  region = var.aws_region
}

# Generate a unique suffix for resource names to avoid collisions
resource "random_id" "suffix" {
  byte_length = 4
}

# Data source for current region
data "aws_region" "current" {}

locals {
  name_prefix = "${var.project_name}-${random_id.suffix.hex}"

  common_tags = {
    Project     = var.project_name
    ManagedBy   = "OpenTofu"
    Component   = "epithet"
  }

  # Lambda Web Adapter layer ARN for arm64
  lambda_web_adapter_layer_arn = "arn:aws:lambda:${data.aws_region.current.name}:753240598075:layer:LambdaAdapterLayerArm64:25"
}
