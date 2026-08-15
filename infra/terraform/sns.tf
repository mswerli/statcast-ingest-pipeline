resource "aws_sns_topic" "game_completed" {
  name = "${var.project}-game-completed"

  tags = local.common_tags
}

# SQS queue as the subscription target for the extractor Lambda
# gives us retry behavior and visibility into failures
resource "aws_sqs_queue" "game_completed" {
  name                       = "${var.project}-game-completed"
  message_retention_seconds  = 86400  # 1 day
  visibility_timeout_seconds = 360    # 6 minutes — should exceed Lambda timeout

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.game_completed_dlq.arn
    maxReceiveCount     = 3
  })

  tags = local.common_tags
}

# dead letter queue — messages land here after 3 failed processing attempts
resource "aws_sqs_queue" "game_completed_dlq" {
  name                      = "${var.project}-game-completed-dlq"
  message_retention_seconds = 1209600  # 14 days — enough time to investigate

  tags = local.common_tags
}

# allow SNS to write to SQS
resource "aws_sqs_queue_policy" "game_completed" {
  queue_url = aws_sqs_queue.game_completed.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "sns.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.game_completed.arn
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = aws_sns_topic.game_completed.arn
          }
        }
      }
    ]
  })
}

# wire SNS -> SQS
resource "aws_sns_topic_subscription" "game_completed_sqs" {
  topic_arn = aws_sns_topic.game_completed.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.game_completed.arn
}
