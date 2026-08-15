variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "baseball-datalake"
}

variable "enable_scheduler" {
  description = "Set to false for local development — EventBridge Scheduler not available in LocalStack free tier"
  type        = bool
  default     = true
}

variable "aws_profile" {
  default = "baseball-lake"
}

variable "localstack_enabled" {
  type    = bool
  default = false
}

# ---------------------------------------------------------------------------
# Snowflake storage integration (see snowflake.tf)
# ---------------------------------------------------------------------------

variable "snowflake_storage_prefixes" {
  description = "S3 key prefixes (no leading slash, trailing slash, no wildcard) Snowflake is allowed to read via the storage integration"
  type        = list(string)
  default     = ["raw/", "processed/", "play-by-play/"]
}

variable "snowflake_storage_aws_iam_user_arn" {
  description = <<-EOT
    STORAGE_AWS_IAM_USER_ARN from `DESC STORAGE INTEGRATION`. Empty string
    until the Snowflake-side integration exists (see
    snowflake-storage-integration.md) — IAM rejects made-up account IDs as a
    trust principal, so snowflake.tf falls back to this account's own root
    ARN as the placeholder until the real value is set and re-applied.
  EOT
  type        = string
  default     = ""
}

variable "snowflake_storage_aws_external_id" {
  description = "STORAGE_AWS_EXTERNAL_ID from `DESC STORAGE INTEGRATION`. Placeholder until set — see snowflake_storage_aws_iam_user_arn."
  type        = string
  default     = "placeholder-until-integration-created"
}
