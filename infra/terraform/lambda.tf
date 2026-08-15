locals {
  # Resolved at plan time; abspath ensures consistent behaviour regardless of cwd
  poller_zip_path       = abspath("${path.root}/../../.build/poller.zip")
  play_by_play_zip_path = abspath("${path.root}/../../.build/play-by-play.zip")
}

resource "aws_iam_role" "poller" {
  count = var.localstack_enabled ? 0 : 1
  name  = "${var.project}-poller-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "poller_basic_execution" {
  count      = var.localstack_enabled ? 0 : 1
  role       = aws_iam_role.poller[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "poller_data_access" {
  count = var.localstack_enabled ? 0 : 1
  name  = "poller-data-access"
  role  = aws_iam_role.poller[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.data_lake.arn}/processed/*"
      },
      {
        # s3:ListBucket on the bucket (not objects) is required for HeadObject
        # to return 404 on missing keys — without it, S3 returns 403 to prevent
        # bucket enumeration, which breaks the is_already_processed check.
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = aws_s3_bucket.data_lake.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["processed/*"]
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.game_completed.arn
      }
    ]
  })
}

resource "aws_s3_object" "poller_code" {
  count = var.localstack_enabled ? 0 : 1

  bucket = aws_s3_bucket.data_lake.bucket
  key    = "code/poller.zip"
  source = local.poller_zip_path
  # try() guards against the file not existing when pointed at LocalStack
  etag = try(filemd5(local.poller_zip_path), "")

  tags = local.common_tags
}

resource "aws_lambda_function" "poller" {
  count = var.localstack_enabled ? 0 : 1

  function_name                  = "${var.project}-poller"
  role                           = aws_iam_role.poller[0].arn
  handler                        = "app.handler"
  runtime                        = "python3.12"
  timeout                        = 300
  memory_size                    = 128
  architectures                  = ["x86_64"]
  reserved_concurrent_executions = 1  # scheduled job — never needs more than one

  s3_bucket        = aws_s3_object.poller_code[0].bucket
  s3_key           = aws_s3_object.poller_code[0].key
  source_code_hash = try(filebase64sha256(local.poller_zip_path), "")

  environment {
    variables = {
      SNS_TOPIC_ARN           = aws_sns_topic.game_completed.arn
      S3_BUCKET               = aws_s3_bucket.data_lake.bucket
      POWERTOOLS_SERVICE_NAME = "baseball-poller"
      POWERTOOLS_LOG_LEVEL    = "INFO"
    }
  }

  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Play-by-play Lambda
# ---------------------------------------------------------------------------

resource "aws_iam_role" "play_by_play" {
  count = var.localstack_enabled ? 0 : 1
  name  = "${var.project}-play-by-play-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "play_by_play_basic_execution" {
  count      = var.localstack_enabled ? 0 : 1
  role       = aws_iam_role.play_by_play[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "play_by_play_sqs_execution" {
  count      = var.localstack_enabled ? 0 : 1
  role       = aws_iam_role.play_by_play[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaSQSQueueExecutionRole"
}

resource "aws_iam_role_policy" "play_by_play_data_access" {
  count = var.localstack_enabled ? 0 : 1
  name  = "play-by-play-data-access"
  role  = aws_iam_role.play_by_play[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject"]
      Resource = "${aws_s3_bucket.data_lake.arn}/play-by-play/*"
    }]
  })
}

resource "aws_s3_object" "play_by_play_code" {
  count = var.localstack_enabled ? 0 : 1

  bucket = aws_s3_bucket.data_lake.bucket
  key    = "code/play-by-play.zip"
  source = local.play_by_play_zip_path
  etag   = try(filemd5(local.play_by_play_zip_path), "")

  tags = local.common_tags
}

resource "aws_lambda_function" "play_by_play" {
  count = var.localstack_enabled ? 0 : 1

  function_name                  = "${var.project}-play-by-play"
  role                           = aws_iam_role.play_by_play[0].arn
  handler                        = "app.lambda_handler"
  runtime                        = "python3.12"
  timeout                        = 300
  memory_size                    = 1024
  architectures                  = ["arm64"]
  reserved_concurrent_executions = 5  # caps parallel game fetches; SQS will queue the rest

  s3_bucket        = aws_s3_object.play_by_play_code[0].bucket
  s3_key           = aws_s3_object.play_by_play_code[0].key
  source_code_hash = try(filebase64sha256(local.play_by_play_zip_path), "")

  environment {
    variables = {
      S3_BUCKET               = aws_s3_bucket.data_lake.bucket
      POWERTOOLS_SERVICE_NAME = "baseball-play-by-play"
      POWERTOOLS_LOG_LEVEL    = "INFO"
    }
  }

  tags = local.common_tags
}

resource "aws_lambda_event_source_mapping" "play_by_play_sqs" {
  count = var.localstack_enabled ? 0 : 1

  event_source_arn        = aws_sqs_queue.game_completed.arn
  function_name           = aws_lambda_function.play_by_play[0].arn
  batch_size              = 10
  function_response_types = ["ReportBatchItemFailures"]
}
