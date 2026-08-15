# IAM role that EventBridge Scheduler uses to invoke the Lambda
resource "aws_iam_role" "scheduler" {
  count = var.enable_scheduler ? 1 : 0
  name  = "${var.project}-scheduler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "scheduler_invoke_lambda" {
  count = var.enable_scheduler ? 1 : 0
  name  = "invoke-poller-lambda"
  role  = aws_iam_role.scheduler[count.index].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = try(aws_lambda_function.poller[0].arn, "")
      }
    ]
  })
}

resource "aws_scheduler_schedule" "baseball_poller" {
  count      = var.enable_scheduler ? 1 : 0
  name       = "${var.project}-poller"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "rate(6 hours)"
  schedule_expression_timezone = "America/New_York"

  target {
    arn      = try(aws_lambda_function.poller[0].arn, "")
    role_arn = aws_iam_role.scheduler[count.index].arn
    input    = "{}"

    retry_policy {
      maximum_retry_attempts = 2
    }
  }
}
