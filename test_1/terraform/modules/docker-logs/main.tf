# terraform/modules/docker-logs/main.tf

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

########################
# 1. CloudWatch Log Group
########################

resource "aws_cloudwatch_log_group" "docker_app" {
  name              = "/docker/${var.env}/${var.service_name}"
  retention_in_days = var.log_group_retention_days

  tags = {
    Environment = var.env
    Service     = var.service_name
  }
}

########################
# 2. IAM Role for EC2 (Docker Host)
########################

# EC2 assume role policy
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# 建立 EC2 用的 IAM Role
resource "aws_iam_role" "docker_logs_role" {
  count = var.create_ec2_iam_role ? 1 : 0

  name               = "docker-logs-role-${var.env}-${var.service_name}"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Environment = var.env
    Service     = var.service_name
  }
}

# 允許將 log 寫入 CloudWatch Logs 的 policy
data "aws_iam_policy_document" "docker_logs_policy" {
  statement {
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams"
    ]

    # 為簡化作業，將權限鎖在這個 log group 底下
    resources = [
      aws_cloudwatch_log_group.docker_app.arn,
      "${aws_cloudwatch_log_group.docker_app.arn}:*"
    ]
  }
}

resource "aws_iam_policy" "docker_logs_policy" {
  count = var.create_ec2_iam_role ? 1 : 0

  name        = "docker-logs-policy-${var.env}-${var.service_name}"
  description = "Allow EC2 Docker host to push logs to CloudWatch Logs"
  policy      = data.aws_iam_policy_document.docker_logs_policy.json
}

resource "aws_iam_role_policy_attachment" "docker_logs_attach" {
  count = var.create_ec2_iam_role ? 1 : 0

  role       = aws_iam_role.docker_logs_role[0].name
  policy_arn = aws_iam_policy.docker_logs_policy[0].arn
}

########################
# 3. Metric Filter & Alarm
########################

# Metric filter: 每當 log line 包含 "ERROR"，就計數 + 1
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "${var.env}-${var.service_name}-error-count"
  log_group_name = aws_cloudwatch_log_group.docker_app.name
  pattern        = "\"ERROR\""

  metric_transformation {
    name      = "ErrorCount"
    namespace = "DockerApp/${var.env}/${var.service_name}"
    value     = "1"
  }
}

# SNS Topic for alarm
resource "aws_sns_topic" "alarm_topic" {
  name = "docker-logs-alarm-${var.env}-${var.service_name}"
}

resource "aws_sns_topic_subscription" "alarm_email" {
  topic_arn = aws_sns_topic.alarm_topic.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# CloudWatch Alarm: 5 分鐘內 Error >= 10 就通知
resource "aws_cloudwatch_metric_alarm" "error_alarm" {
  alarm_name          = "docker-error-${var.env}-${var.service_name}"
  alarm_description   = "Docker logs ERROR count high for ${var.env}/${var.service_name}"
  namespace           = "DockerApp/${var.env}/${var.service_name}"
  metric_name         = "ErrorCount"
  statistic           = "Sum"
  period              = 300               # 5 分鐘
  evaluation_periods  = 1
  threshold           = 10
  comparison_operator = "GreaterThanOrEqualToThreshold"

  alarm_actions = [aws_sns_topic.alarm_topic.arn]

  treat_missing_data = "notBreaching"
}

########################
# 4. CloudWatch Dashboard
########################

resource "aws_cloudwatch_dashboard" "docker_logs_dashboard" {
  dashboard_name = "docker-logs-${var.env}-${var.service_name}"

  dashboard_body = jsonencode({
    widgets = [
      {
        "type" : "metric",
        "x" : 0,
        "y" : 0,
        "width" : 12,
        "height" : 6,
        "properties" : {
          "title" : "ErrorCount (${var.env}/${var.service_name})",
          "region" : data.aws_region.current.name,
          "metrics" : [
            [ "DockerApp/${var.env}/${var.service_name}", "ErrorCount", { "stat" : "Sum" } ]
          ],
          "period" : 300,
          "stacked" : false
        }
      },
      {
        "type" : "log",
        "x" : 0,
        "y" : 6,
        "width" : 24,
        "height" : 6,
        "properties" : {
          "title" : "Recent ERROR logs",
          "query" : "SOURCE '${aws_cloudwatch_log_group.docker_app.name}' | filter @message like /ERROR/ | sort @timestamp desc | limit 20",
          "region" : data.aws_region.current.name,
          "view" : "table"
        }
      }
    ]
  })
}
