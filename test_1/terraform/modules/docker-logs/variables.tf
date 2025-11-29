# terraform/modules/docker-logs/variables.tf

variable "env" {
  description = "Environment name (dev/uat/prod)"
  type        = string
}

variable "service_name" {
  description = "Docker service name"
  type        = string
}

variable "log_group_retention_days" {
  description = "CloudWatch Logs retention in days"
  type        = number
  default     = 30
}

variable "alarm_email" {
  description = "Email address to receive CloudWatch alarms"
  type        = string
}

variable "create_ec2_iam_role" {
  description = "Whether to create IAM role for EC2 Docker hosts"
  type        = bool
  default     = true
}
