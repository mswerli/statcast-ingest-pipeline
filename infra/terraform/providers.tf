provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  # LocalStack override — only set when running locally
  dynamic "endpoints" {
    for_each = var.localstack_enabled ? [1] : []
    content {
      s3       = "http://localhost:4566"
      lambda   = "http://localhost:4566"
      sns      = "http://localhost:4566"
      sqs      = "http://localhost:4566"
      dynamodb = "http://localhost:4566"
      iam      = "http://localhost:4566"
      events   = "http://localhost:4566"
      sts      = "http://localhost:4566"
    }
  }

  # Required for LocalStack — stops Terraform validating real AWS account IDs
  skip_credentials_validation = var.localstack_enabled
  skip_requesting_account_id  = var.localstack_enabled
  skip_metadata_api_check     = var.localstack_enabled

  # LocalStack needs this for S3
  s3_use_path_style = var.localstack_enabled
}