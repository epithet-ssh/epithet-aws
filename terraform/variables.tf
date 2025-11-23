variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Project name used in resource naming"
  type        = string
  default     = "epithet"
}

variable "lambda_memory_mb" {
  description = "Lambda function memory allocation in MB"
  type        = number
  default     = 256
}

variable "lambda_timeout_sec" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention period in days"
  type        = number
  default     = 7
}

variable "cert_archive_retention_days" {
  description = "Certificate archive retention period in days (0 = keep forever)"
  type        = number
  default     = 0
}
