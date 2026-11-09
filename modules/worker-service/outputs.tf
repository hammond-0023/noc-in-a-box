output "service_name" {
  value = aws_ecs_service.this.name
}

output "task_role_name" {
  value = aws_iam_role.task.name
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.this.name
}
