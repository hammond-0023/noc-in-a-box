# Alert routing: alarms -> SNS topic -> email (optional).
resource "aws_sns_topic" "alerts" {
  name = "${local.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# P2: users are getting server errors.
resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  alarm_name          = "${local.name}-api-5xx"
  alarm_description   = "P2: API returning 5xx. Runbook: docs/runbooks/api-5xx.md"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HTTPCode_Target_5XX_Count"
  dimensions          = { LoadBalancer = module.api.alb_arn_suffix }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# P1: no healthy tasks behind the load balancer.
resource "aws_cloudwatch_metric_alarm" "api_unhealthy" {
  alarm_name        = "${local.name}-api-unhealthy-hosts"
  alarm_description = "P1: unhealthy API tasks. Runbook: docs/runbooks/crash-loop.md"
  namespace         = "AWS/ApplicationELB"
  metric_name       = "UnHealthyHostCount"
  dimensions = {
    LoadBalancer = module.api.alb_arn_suffix
    TargetGroup  = module.api.target_group_arn_suffix
  }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# P2: an order failed three times and was parked in the DLQ.
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${local.name}-dlq-not-empty"
  alarm_description   = "P2: messages in the dead-letter queue. Runbook: docs/runbooks/dlq.md"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.orders_dlq.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# P3: the worker is falling behind (or is down).
resource "aws_cloudwatch_metric_alarm" "queue_age" {
  alarm_name          = "${local.name}-queue-oldest-message-age"
  alarm_description   = "P3: orders waiting too long. Runbook: docs/runbooks/stuck-queue.md"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  dimensions          = { QueueName = aws_sqs_queue.orders.name }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 120
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# P3: sustained high CPU on the API.
resource "aws_cloudwatch_metric_alarm" "api_cpu" {
  alarm_name        = "${local.name}-api-cpu-high"
  alarm_description = "P3: API CPU above 80% for 15 minutes."
  namespace         = "AWS/ECS"
  metric_name       = "CPUUtilization"
  dimensions = {
    ClusterName = module.api.cluster_name
    ServiceName = module.api.service_name
  }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# One screen for the on-call engineer.
resource "aws_cloudwatch_dashboard" "noc" {
  dashboard_name = "${local.name}-noc"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "API requests and 5xx"
          region = var.region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", module.api.alb_arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count", "LoadBalancer", module.api.alb_arn_suffix],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "API latency p95 (seconds)"
          region = var.region
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", module.api.alb_arn_suffix, { stat = "p95" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Orders queue: depth and age"
          region = var.region
          period = 60
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.orders.name, { stat = "Maximum" }],
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", aws_sqs_queue.orders.name, { stat = "Maximum", yAxis = "right" }],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Dead-letter queue depth"
          region = var.region
          period = 60
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", aws_sqs_queue.orders_dlq.name, { stat = "Maximum" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 12, width = 12, height = 6
        properties = {
          title  = "ECS CPU %"
          region = var.region
          period = 60
          stat   = "Average"
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", module.api.cluster_name, "ServiceName", module.api.service_name],
            ["AWS/ECS", "CPUUtilization", "ClusterName", module.api.cluster_name, "ServiceName", module.worker.service_name],
          ]
        }
      },
      {
        type = "alarm", x = 12, y = 12, width = 12, height = 6
        properties = {
          title = "Alarm status"
          alarms = [
            aws_cloudwatch_metric_alarm.api_5xx.arn,
            aws_cloudwatch_metric_alarm.api_unhealthy.arn,
            aws_cloudwatch_metric_alarm.dlq_not_empty.arn,
            aws_cloudwatch_metric_alarm.queue_age.arn,
            aws_cloudwatch_metric_alarm.api_cpu.arn,
          ]
        }
      },
    ]
  })
}
