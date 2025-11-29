# terraform/live/root.hcl

remote_state {
  backend = "s3"

  config = {
    bucket         = "weihan-tf-state-bucket"            # TODO: 換成你自己的 S3 bucket
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "ap-northeast-1"                    # TODO: 換成你自己的region
    dynamodb_table = "weihan-tf-lock-table"              # TODO: 換成你自己的 DynamoDB table
    encrypt        = true
  }
}

locals {
  aws_region = "ap-northeast-1"                         # TODO: 換成你自己的region
}

# 自動產生 provider 設定檔，讓各 module 可以直接用
generate "provider" {
  path      = "provider.generated.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "${local.aws_region}"
}
EOF
}
