output "app_url" {
  value = "http://${module.api.alb_dns_name}"
}

output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}

output "cluster_name" {
  value = module.api.cluster_name
}

output "service_name" {
  value = module.api.service_name
}

output "worker_service_name" {
  value = module.worker.service_name
}

output "orders_queue_url" {
  value = aws_sqs_queue.orders.url
}

output "orders_dlq_url" {
  value = aws_sqs_queue.orders_dlq.url
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.noc.dashboard_name
}
