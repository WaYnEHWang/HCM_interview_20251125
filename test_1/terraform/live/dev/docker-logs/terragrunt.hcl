include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path   = find_in_parent_folders("env.hcl")
  expose = true
}

terraform {
  source = "${get_terragrunt_dir()}/../../../modules/docker-logs"
}

# 把 env.hcl 裡的 locals 拉進來
locals {
  # 這行會拿到 env.hcl 裡全部 locals 的集合
  env_vars = include.env.locals

  env                = local.env_vars.environment
  log_retention_days = local.env_vars.log_retention_days
  alarm_email        = local.env_vars.alarm_email
}

inputs = {
  env                      = local.env
  service_name             = "hcm-api"             # TODO: 你的 Docker 服務名稱
  log_group_retention_days = local.log_retention_days
  alarm_email              = local.alarm_email

  # 若你已經有現成 EC2 IAM Role，不想 Terraform 建新的，就改成 false
  create_ec2_iam_role      = true
}
