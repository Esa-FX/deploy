variable "aws_region" {
  description = "Primary AWS region (Jakarta)"
  type        = string
  default     = "ap-southeast-3"
}

variable "environment" {
  description = "Environment name used in resource naming"
  type        = string
  default     = "production"
}

variable "project" {
  description = "Project prefix for resource names"
  type        = string
  default     = "esafx"
}

variable "domain_name" {
  description = "Root domain (must exist in Route 53 in this account)"
  type        = string
  default     = "esandardev.com"
}

variable "api_hostname" {
  description = "Public API hostname"
  type        = string
  default     = "api.esandardev.com"
}

variable "crm_hostname" {
  description = "Public CRM SPA hostname"
  type        = string
  default     = "crm.esandardev.com"
}

variable "vpc_cidr" {
  description = "Production VPC CIDR (distinct from staging 10.0.0.0/16)"
  type        = string
  default     = "10.1.0.0/16"
}

variable "linux_instance_type" {
  description = "Instance type for core, crm, and voip EC2 (scale up later)"
  type        = string
  default     = "t3.small"
}

variable "windows_instance_type" {
  description = "Instance type for MT bridge Windows EC2"
  type        = string
  default     = "t3.small"
}

variable "db_instance_class" {
  description = "RDS instance class for core and trading databases"
  type        = string
  default     = "db.t3.small"
}

variable "redis_node_type" {
  description = "ElastiCache Redis node type"
  type        = string
  default     = "cache.t3.small"
}

variable "db_allocated_storage_gb" {
  description = "Initial RDS storage (GB)"
  type        = number
  default     = 50
}

variable "db_multi_az" {
  description = "Enable Multi-AZ RDS (recommended for prod; off initially to save cost)"
  type        = bool
  default     = false
}

variable "ssh_key_name" {
  description = "Optional EC2 key pair name for emergency SSH (SSM preferred)"
  type        = string
  default     = null
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach ALB HTTPS (restrict in prod if possible)"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "create_route53_records" {
  description = "Create Route 53 alias records for api and crm hostnames"
  type        = bool
  default     = true
}

variable "create_acm_certificates" {
  description = "Request ACM certificates via DNS validation (requires Route 53 zone)"
  type        = bool
  default     = true
}

variable "alb_certificate_arn" {
  description = "Existing ACM cert ARN in ap-southeast-3 for ALB (if create_acm_certificates=false)"
  type        = string
  default     = null
}

variable "cloudfront_certificate_arn" {
  description = "Existing ACM cert ARN in us-east-1 for CloudFront (if create_acm_certificates=false)"
  type        = string
  default     = null
}

variable "cognito_callback_urls" {
  description = "Cognito app client callback URLs"
  type        = list(string)
  default     = ["https://crm.esandardev.com"]
}

variable "cognito_logout_urls" {
  description = "Cognito app client logout URLs"
  type        = list(string)
  default     = ["https://crm.esandardev.com"]
}

variable "core_db_name" {
  type    = string
  default = "esafx_core"
}

variable "trading_db_name" {
  type    = string
  default = "esafx_trading"
}

variable "db_master_username" {
  type    = string
  default = "dbadmin"
}
