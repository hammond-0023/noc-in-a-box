# Datadog monitors and dashboard, defined as code.
# Metrics come from the Datadog AWS integration (CloudWatch), so they arrive
# with a delay of several minutes. Verify tag names in Datadog's Metrics Explorer
# (for example aws.applicationelb.request_count, group by "name").

locals {
  dd_notify = var.alert_email == "" ? "" : "@${var.alert_email}"
  dd_tags   = ["service:noc-dev", "env:dev", "managed-by:terraform"]

  # Noisy "before" vs tuned "after" settings for the 5xx monitor.
  five_xx_window    = var.tuned_alerts ? "last_5m" : "last_1m"
  five_xx_threshold = var.tuned_alerts ? 5 : 0
}

# P2: users are getting server errors.
# NOISY version (tuned_alerts = false): fires on a single 5xx in one minute.
# TUNED version (tuned_alerts = true): needs more than 5 errors over 5 minutes.
resource "datadog_monitor" "api_5xx" {
  name    = "[P2] noc-dev API returning 5xx${var.tuned_alerts ? "" : " (noisy)"}"
  type    = "metric alert"
  message = <<-EOT
    P2: the API is returning 5xx errors. Runbook: docs/runbooks/api-5xx.md
    First check: recent deploy, then ECS service events and application logs.
    ${local.dd_notify}
  EOT

  query = "sum(${local.five_xx_window}):sum:aws.applicationelb.httpcode_target_5xx{name:noc-dev}.as_count() > ${local.five_xx_threshold}"

  monitor_thresholds {
    critical = local.five_xx_threshold
  }

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.dd_tags, ["severity:p2"])
}

# P1: no healthy tasks behind the load balancer.
resource "datadog_monitor" "api_unhealthy" {
  name    = "[P1] noc-dev unhealthy API tasks"
  type    = "metric alert"
  message = <<-EOT
    P1: one or more API tasks are failing health checks. Runbook: docs/runbooks/crash-loop.md
    ${local.dd_notify}
  EOT

  query = "max(last_5m):max:aws.applicationelb.un_healthy_host_count{name:noc-dev} >= 1"

  monitor_thresholds {
    critical = 1
  }

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.dd_tags, ["severity:p1"])
}

# P2: an order failed three times and was parked in the dead-letter queue.
resource "datadog_monitor" "dlq_not_empty" {
  name    = "[P2] noc-dev dead-letter queue not empty"
  type    = "metric alert"
  message = <<-EOT
    P2: orders are in the dead-letter queue. Runbook: docs/runbooks/dlq.md
    ${local.dd_notify}
  EOT

  query = "max(last_5m):max:aws.sqs.approximate_number_of_messages_visible{queuename:noc-dev-orders-dlq} > 0"

  monitor_thresholds {
    critical = 0
  }

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.dd_tags, ["severity:p2"])
}

# P3: the worker is falling behind or is down.
resource "datadog_monitor" "queue_age" {
  name    = "[P3] noc-dev orders waiting too long"
  type    = "metric alert"
  message = <<-EOT
    P3: the oldest order has waited over 2 minutes. Runbook: docs/runbooks/stuck-queue.md
    ${local.dd_notify}
  EOT

  query = "max(last_5m):max:aws.sqs.approximate_age_of_oldest_message{queuename:noc-dev-orders} > 120"

  monitor_thresholds {
    critical = 120
  }

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.dd_tags, ["severity:p3"])
}

# P3: slow responses, tuned to ignore short blips.
resource "datadog_monitor" "api_latency" {
  name    = "[P3] noc-dev API latency high"
  type    = "metric alert"
  message = <<-EOT
    P3: average response time above 500 ms for 10 minutes. Runbook: docs/runbooks/api-5xx.md
    ${local.dd_notify}
  EOT

  query = "avg(last_10m):avg:aws.applicationelb.target_response_time.average{name:noc-dev} > 0.5"

  monitor_thresholds {
    critical = 0.5
  }

  notify_no_data      = false
  require_full_window = false
  tags                = concat(local.dd_tags, ["severity:p3"])
}

resource "datadog_dashboard_json" "noc" {
  dashboard = jsonencode({
    title       = "noc-dev NOC"
    description = "On-call view: traffic, errors, latency, queue health and monitor status."
    layout_type = "ordered"
    widgets = [
      {
        definition = {
          type  = "timeseries"
          title = "API requests and 5xx"
          requests = [
            { q = "sum:aws.applicationelb.request_count{name:noc-dev}.as_count()", display_type = "bars" },
            { q = "sum:aws.applicationelb.httpcode_target_5xx{name:noc-dev}.as_count()", display_type = "bars" },
          ]
        }
      },
      {
        definition = {
          type  = "timeseries"
          title = "API response time (seconds)"
          requests = [
            { q = "avg:aws.applicationelb.target_response_time.average{name:noc-dev}", display_type = "line" },
          ]
        }
      },
      {
        definition = {
          type  = "timeseries"
          title = "Orders queue: depth and age"
          requests = [
            { q = "max:aws.sqs.approximate_number_of_messages_visible{queuename:noc-dev-orders}", display_type = "line" },
            { q = "max:aws.sqs.approximate_age_of_oldest_message{queuename:noc-dev-orders}", display_type = "line" },
          ]
        }
      },
      {
        definition = {
          type  = "timeseries"
          title = "Dead-letter queue depth"
          requests = [
            { q = "max:aws.sqs.approximate_number_of_messages_visible{queuename:noc-dev-orders-dlq}", display_type = "bars" },
          ]
        }
      },
      {
        definition = {
          type             = "manage_status"
          title            = "Monitors"
          display_format   = "countsAndList"
          query            = "tag:(service:noc-dev)"
          summary_type     = "monitors"
          sort             = "status,asc"
          color_preference = "text"
          hide_zero_counts = true
        }
      },
    ]
  })
}
