output "data_lake_bucket_name" {
  description = "S3 data lake bucket name"
  value       = aws_s3_bucket.data_lake.bucket
}

output "data_lake_bucket_arn" {
  description = "S3 data lake bucket ARN"
  value       = aws_s3_bucket.data_lake.arn
}

output "game_completed_topic_arn" {
  description = "SNS topic ARN for completed game events"
  value       = aws_sns_topic.game_completed.arn
}

output "game_completed_queue_url" {
  description = "SQS queue URL for game completed events"
  value       = aws_sqs_queue.game_completed.url
}

output "game_completed_dlq_url" {
  description = "SQS dead letter queue URL"
  value       = aws_sqs_queue.game_completed_dlq.url
}

output "poller_lambda_arn" {
  description = "Poller Lambda function ARN (empty when pointed at LocalStack)"
  value       = try(aws_lambda_function.poller[0].arn, "")
}

output "play_by_play_lambda_arn" {
  description = "Play-by-play Lambda function ARN (empty when pointed at LocalStack)"
  value       = try(aws_lambda_function.play_by_play[0].arn, "")
}
