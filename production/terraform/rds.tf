# Ops alerting is NOT managed here yet. The RDS event subscription `esafx-prod-rds-events`
# (RDS -> aws_sns_topic.ops, categories: configuration change, failure, low storage,
# maintenance) was created by CLI on 2026-11-16 and is absent from state. If you add an
# aws_db_event_subscription resource below, `terraform import` it first, otherwise the
# plan will try to create a duplicate and fail on SubscriptionAlreadyExists:
#   terraform import aws_db_event_subscription.rds_events esafx-prod-rds-events
#
# The `backup` category is deliberately excluded: it emits RDS-EVENT-0001 "Backing up DB
# instance" and RDS-EVENT-0002 "Finished DB instance backup" on every automated backup
# (8 event emails a day across the four instances) plus two per manual snapshot, and RDS
# publishes no backup-failure event to replace them. Backup freshness has to be checked,
# not awaited: LatestRestorableTime should be minutes behind now.
#
# Pre-change snapshots: ops/rds/rds-prechange-snapshot.ps1.

resource "random_password" "core_db" {
  length  = 32
  special = false
}

resource "random_password" "trading_db" {
  length  = 32
  special = false
}

resource "random_password" "trading_readonly_db" {
  length  = 32
  special = false
}

resource "random_password" "service_tokens" {
  length  = 48
  special = false
}

resource "random_password" "crm_internal" {
  length  = 48
  special = false
}

resource "random_password" "mt_bridge_crm" {
  length  = 48
  special = false
}

resource "random_password" "mt_bridge_client" {
  length  = 48
  special = false
}

resource "random_password" "mt_bridge_admin" {
  length  = 48
  special = false
}

resource "random_password" "dealer_webhook" {
  length  = 48
  special = false
}

resource "random_password" "audit_api_key" {
  length  = 48
  special = false
}

resource "aws_db_instance" "core" {
  identifier     = "${local.name_prefix}-core"
  engine         = "postgres"
  engine_version = "16.9"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage_gb
  max_allocated_storage = var.db_allocated_storage_gb * 2
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.main.arn

  db_name  = var.core_db_name
  username = var.db_master_username
  password = random_password.core_db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period   = 7
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name_prefix}-core-final"
  deletion_protection       = true

  parameter_group_name = "default.postgres16"
  apply_immediately    = false

  lifecycle {
    ignore_changes = [engine_version, instance_class]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-core"
  })
}

resource "aws_db_instance" "trading" {
  identifier     = "${local.name_prefix}-trading"
  engine         = "postgres"
  engine_version = "16.9"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage_gb
  max_allocated_storage = var.db_allocated_storage_gb * 2
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = aws_kms_key.main.arn

  db_name  = var.trading_db_name
  username = var.db_master_username
  password = random_password.trading_db.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  multi_az               = var.db_multi_az

  backup_retention_period   = 7
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name_prefix}-trading-final"
  deletion_protection       = true

  parameter_group_name = "default.postgres16"
  apply_immediately    = false

  lifecycle {
    ignore_changes = [engine_version, instance_class]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-trading"
  })
}

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${local.name_prefix}-redis"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = var.redis_node_type
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  port                 = 6379
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-redis"
  })
}
