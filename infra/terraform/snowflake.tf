# ---------------------------------------------------------------------------
# Snowflake storage integration
#
# Grants a Snowflake storage integration read-only access to the data lake
# bucket so it can COPY INTO tables directly from S3, without embedding IAM
# user credentials in Snowflake. Follows:
# https://docs.snowflake.com/en/user-guide/data-load-s3-config-storage-integration
#
# This is a two-phase setup because Snowflake and AWS each need a value the
# other side produces:
#
#   1. `terraform apply` with the default placeholder trust-policy variables
#      below. This creates the IAM role/policy and outputs its ARN.
#   2. In Snowflake, run CREATE STORAGE INTEGRATION using that role ARN (see
#      snowflake-storage-integration.md), then DESC STORAGE INTEGRATION to
#      read back STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID.
#   3. Set snowflake_storage_aws_iam_user_arn / snowflake_storage_aws_external_id
#      (e.g. via -var or a *.tfvars file) to the real values and re-apply —
#      this tightens the trust policy from the placeholder to the actual
#      Snowflake IAM user, which is what makes the assume-role trust work.
# ---------------------------------------------------------------------------

locals {
  # Resource ARNs / list-prefix conditions the Snowflake role is scoped to —
  # the three prefixes the pipeline actually writes (see s3.tf, lambda.tf).
  snowflake_object_arns   = [for p in var.snowflake_storage_prefixes : "${aws_s3_bucket.data_lake.arn}/${p}*"]
  snowflake_list_prefixes = [for p in var.snowflake_storage_prefixes : "${p}*"]
}

resource "aws_iam_role" "snowflake_storage_integration" {
  count = var.localstack_enabled ? 0 : 1
  name  = "${var.project}-snowflake-storage-integration-role"

  # STORAGE_AWS_IAM_USER_ARN / STORAGE_AWS_EXTERNAL_ID start as placeholders
  # (Snowflake doesn't exist yet on first apply) and get tightened once the
  # real values are known — see header comment.
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = var.snowflake_storage_aws_iam_user_arn }
        Action    = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.snowflake_storage_aws_external_id
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "snowflake_storage_integration" {
  count = var.localstack_enabled ? 0 : 1
  name  = "snowflake-storage-access"
  role  = aws_iam_role.snowflake_storage_integration[0].id

  # Read-only: this pipeline uses the integration to load S3 data into
  # Snowflake (COPY INTO), not to unload query results back to S3.
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = local.snowflake_object_arns
      },
      {
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.data_lake.arn
        Condition = {
          StringLike = {
            "s3:prefix" = local.snowflake_list_prefixes
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = "s3:GetBucketLocation"
        Resource = aws_s3_bucket.data_lake.arn
      }
    ]
  })
}
