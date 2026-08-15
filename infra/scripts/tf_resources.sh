#!/usr/bin/env bash

INITIALS=${1}
PROFILE=${2:-baseball-lake}
REGION=${3:-us-east-1}
BUCKET="baseball-lake-tfstate-${INITIALS}"

awslocal s3api create-bucket \
  --bucket "$BUCKET" \
  --region "$REGION" \
  --profile "$PROFILE"

awslocal s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled \
  --profile "$PROFILE"

awslocal dynamodb create-table \
  --table-name baseball-lake-tflock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$REGION" \
  --profile "$PROFILE"