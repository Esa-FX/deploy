data "aws_caller_identity" "current" {}
data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  name_prefix = "${var.project}-${var.environment}"

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnet_cidrs  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnet_cidrs = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  recordings_prefix      = "recordings"
  ftd_uploads_prefix     = "ftd"
  call_recordings_bucket = "${local.name_prefix}-call-recordings-${local.account_id}"
  ftd_uploads_bucket     = "${local.name_prefix}-ftd-uploads-${local.account_id}"
  crm_frontend_bucket    = "${local.name_prefix}-crm-frontend-${local.account_id}"
  kyc_docs_bucket        = "esafx-kyc-docs-production-${local.account_id}"
  agreements_bucket      = "esafx-signed-agreements-production-${local.account_id}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
