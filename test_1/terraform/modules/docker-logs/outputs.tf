# terraform/modules/docker-logs/outputs.tf

output "log_group_name" {
  description = "CloudWatch Logs log group name for Docker service"
  value       = aws_cloudwatch_log_group.docker_app.name
}

output "ec2_iam_role_name" {
  description = "IAM role name for EC2 Docker hosts (attach this to instance profile)"
  value       = var.create_ec2_iam_role ? aws_iam_role.docker_logs_role[0].name : null
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alarms"
  value       = aws_sns_topic.alarm_topic.arn
}

output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.docker_logs_dashboard.dashboard_name
}
