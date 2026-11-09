# Failed messages are retried, then parked in the dead-letter queue (DLQ)
# so one bad order can't block the rest. A non-empty DLQ is an alert.
resource "aws_sqs_queue" "orders_dlq" {
  name                      = "${local.name}-orders-dlq"
  message_retention_seconds = 1209600 # 14 days
}

resource "aws_sqs_queue" "orders" {
  name                       = "${local.name}-orders"
  visibility_timeout_seconds = 30

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_dynamodb_table" "orders" {
  name         = "${local.name}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }
}
