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
