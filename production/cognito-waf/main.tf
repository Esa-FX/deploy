terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-3"
}

variable "environment" {
  type    = string
  default = "production"
}

variable "user_pool_ids" {
  description = "Existing Cognito user pool IDs. Append new production pools here and re-apply."
  type        = list(string)
}

data "aws_cognito_user_pool" "pools" {
  for_each     = toset(var.user_pool_ids)
  user_pool_id = each.value
}

module "cognito_waf" {
  source = "../../modules/cognito-waf"

  name = "esafx-${var.environment}-cognito"
  user_pool_arns = [
    for id in var.user_pool_ids : data.aws_cognito_user_pool.pools[id].arn
  ]

  tags = {
    Project     = "esafx"
    Environment = var.environment
    ManagedBy   = "terraform"
    Purpose     = "cognito-login-waf"
  }
}

output "web_acl_arn" {
  value = module.cognito_waf.web_acl_arn
}

output "associated_user_pool_arns" {
  value = module.cognito_waf.associated_user_pool_arns
}
