terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

variable "instance_type" {
  description = "t3.nano (0.5GiB) and t3.micro (1GiB) OOM with app+Postgres+Redis+AL2023. t3.small (2GiB) is the floor."
  type        = string
  default     = "t3.small"
}

variable "wiki_hostname" {
  type    = string
  default = "wiki.esandardev.com"
}

variable "domain_name" {
  type    = string
  default = "esandardev.com"
}

variable "alb_name" {
  type    = string
  default = "esafx-production-api-alb"
}

variable "listener_rule_priority" {
  type    = number
  default = 3
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "prod" {
  filter {
    name   = "tag:Name"
    values = ["esafx-production-vpc"]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.prod.id]
  }
  filter {
    name   = "tag:Name"
    values = ["esafx-production-private-*"]
  }
}

data "aws_security_group" "alb" {
  filter {
    name   = "group-name"
    values = ["esafx-production-alb-sg"]
  }
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.prod.id]
  }
}

data "aws_lb" "api" {
  name = var.alb_name
}

data "aws_lb_listener" "https" {
  load_balancer_arn = data.aws_lb.api.arn
  port              = 443
}

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

locals {
  name_prefix = "esafx-${var.environment}-docmost"
  common_tags = {
    Project     = "esafx"
    Environment = var.environment
    Service     = "docmost"
    ManagedBy   = "terraform"
  }
}

resource "random_password" "app_secret" {
  length  = 64
  special = false
}

resource "random_password" "db_password" {
  length  = 32
  special = false
}

resource "aws_secretsmanager_secret" "app_secret" {
  name = "esafx/${var.environment}/docmost/app-secret"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "app_secret" {
  secret_id     = aws_secretsmanager_secret.app_secret.id
  secret_string = random_password.app_secret.result
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "esafx/${var.environment}/docmost/db-password"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db_password.result
}

resource "aws_secretsmanager_secret" "bot" {
  name        = "esafx/${var.environment}/docmost/bot"
  description = "JSON {email,password,url} for the sync bot. Set password after Docmost first-run setup. Do not store in git."
  tags        = local.common_tags
}

resource "aws_secretsmanager_secret_version" "bot" {
  secret_id = aws_secretsmanager_secret.bot.id
  secret_string = jsonencode({
    url      = "https://${var.wiki_hostname}"
    email    = "sairamsalim@esafx.co.id"
    password = "CHANGE_ME_AFTER_DOCMOST_SETUP"
  })
  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_s3_bucket" "sync_state" {
  bucket = "esafx-${var.environment}-docmost-sync-${data.aws_caller_identity.current.account_id}"
  tags   = merge(local.common_tags, { Name = "esafx-${var.environment}-docmost-sync" })
}

resource "aws_s3_bucket_public_access_block" "sync_state" {
  bucket                  = aws_s3_bucket.sync_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sync_state" {
  bucket = aws_s3_bucket.sync_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role" "ec2" {
  name               = "${local.name_prefix}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "runtime" {
  name = "${local.name_prefix}-runtime"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DocmostSecrets"
        Effect   = "Allow"
        Action   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
        Resource = [
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:esafx/${var.environment}/github-clone*",
          "arn:aws:secretsmanager:${var.aws_region}:${data.aws_caller_identity.current.account_id}:secret:esafx/${var.environment}/docmost/*",
        ]
      },
      {
        Sid      = "SyncStateList"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.sync_state.arn
      },
      {
        Sid      = "SyncState"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "${aws_s3_bucket.sync_state.arn}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-profile"
  role = aws_iam_role.ec2.name
}

resource "aws_security_group" "docmost" {
  name        = "${local.name_prefix}-sg"
  description = "Docmost HTTP from production ALB only"
  vpc_id      = data.aws_vpc.prod.id

  ingress {
    description     = "Docmost from ALB"
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [data.aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-sg" })
}

resource "aws_instance" "docmost" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = var.instance_type
  subnet_id              = sort(data.aws_subnets.private.ids)[0]
  vpc_security_group_ids = [aws_security_group.docmost.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    # AL2023 AMI snapshot is 30 GiB; EC2 rejects a smaller root volume.
    volume_size = 30
    volume_type = "gp3"
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail
    dnf update -y
    dnf install -y docker git
    systemctl enable --now docker
    usermod -aG docker ec2-user
    mkdir -p /opt/esafx /var/lib/docmost-src /var/lib/docmost-sync
    echo "esafx docmost host ready (wiki.esandardev.com)"
  EOF

  tags = merge(local.common_tags, {
    Name = "esafx-${var.environment}-docmost"
    Role = "docmost"
  })
}

resource "aws_lb_target_group" "docmost" {
  name     = local.name_prefix
  port     = 3000
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.prod.id

  health_check {
    path                = "/api/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    matcher             = "200"
  }

  stickiness {
    type            = "lb_cookie"
    enabled         = true
    cookie_duration = 86400
  }

  tags = local.common_tags
}

resource "aws_lb_target_group_attachment" "docmost" {
  target_group_arn = aws_lb_target_group.docmost.arn
  target_id        = aws_instance.docmost.id
  port             = 3000
}

# Prod ALB already serves *.esandardev.com — no extra SNI cert.
resource "aws_lb_listener_rule" "wiki" {
  listener_arn = data.aws_lb_listener.https.arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.docmost.arn
  }

  condition {
    host_header {
      values = [var.wiki_hostname]
    }
  }
}

resource "aws_route53_record" "wiki" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = var.wiki_hostname
  type    = "A"

  alias {
    name                   = data.aws_lb.api.dns_name
    zone_id                = data.aws_lb.api.zone_id
    evaluate_target_health = true
  }
}

output "instance_id" {
  value = aws_instance.docmost.id
}

output "private_ip" {
  value = aws_instance.docmost.private_ip
}

output "wiki_url" {
  value = "https://${var.wiki_hostname}"
}

output "bot_secret_name" {
  value = aws_secretsmanager_secret.bot.name
}

output "sync_state_bucket" {
  value = aws_s3_bucket.sync_state.bucket
}
