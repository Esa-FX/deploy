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
