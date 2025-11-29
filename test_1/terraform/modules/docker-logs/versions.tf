# terraform/modules/docker-logs/versions.tf
terraform {
  required_version = ">= 1.3.0"

  backend "s3" {}
}
