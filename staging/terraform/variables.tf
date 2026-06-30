variable "aws_region" {
  description = "AWS region for call recordings bucket"
  type        = string
  default     = "ap-southeast-3"
}

variable "environment" {
  description = "Environment name prefix"
  type        = string
  default     = "staging"
}

variable "app_ec2_role_name" {
  description = "IAM role attached to app EC2 (crm-api, voip-gateway)"
  type        = string
  default     = "esafx-staging-ec2-app-role"
}
