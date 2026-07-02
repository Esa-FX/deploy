resource "aws_kms_key" "main" {
  description             = "${local.name_prefix} encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-kms"
  })
}

resource "aws_kms_alias" "main" {
  name          = "alias/${var.project}-${var.environment}"
  target_key_id = aws_kms_key.main.key_id
}

resource "aws_secretsmanager_secret" "core_db" {
  name = "${var.project}/${var.environment}/db/core"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "core_db" {
  secret_id = aws_secretsmanager_secret.core_db.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.core_db.result
    engine   = "postgres"
    host     = aws_db_instance.core.address
    port     = aws_db_instance.core.port
    dbname   = var.core_db_name
  })
}

resource "aws_secretsmanager_secret" "trading_db" {
  name = "${var.project}/${var.environment}/db/trading"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "trading_db" {
  secret_id = aws_secretsmanager_secret.trading_db.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.trading_db.result
    engine   = "postgres"
    host     = aws_db_instance.trading.address
    port     = aws_db_instance.trading.port
    dbname   = var.trading_db_name
  })
}

resource "aws_secretsmanager_secret" "trading_readonly_db" {
  name = "${var.project}/${var.environment}/db/trading-readonly"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "trading_readonly_db" {
  secret_id = aws_secretsmanager_secret.trading_readonly_db.id
  secret_string = jsonencode({
    username = "crm_trading_readonly"
    password = random_password.trading_readonly_db.result
    engine   = "postgres"
    host     = aws_db_instance.trading.address
    port     = aws_db_instance.trading.port
    dbname   = var.trading_db_name
  })
}

resource "aws_secretsmanager_secret" "service_tokens" {
  name = "${var.project}/${var.environment}/service-tokens"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "service_tokens" {
  secret_id = aws_secretsmanager_secret.service_tokens.id
  secret_string = jsonencode({
    client                  = random_password.service_tokens.result
    mt_bridge               = random_password.service_tokens.result
    pii_vault               = random_password.service_tokens.result
    CLIENT_SERVICE_TOKEN    = random_password.service_tokens.result
    INTERNAL_SERVICE_TOKEN  = random_password.service_tokens.result
    MT_BRIDGE_SERVICE_TOKEN = random_password.service_tokens.result
    PII_VAULT_SERVICE_TOKEN = random_password.service_tokens.result
  })
}

resource "aws_secretsmanager_secret" "audit_api_key" {
  name = "${var.project}/${var.environment}/audit/api-key"
  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "audit_api_key" {
  secret_id     = aws_secretsmanager_secret.audit_api_key.id
  secret_string = random_password.audit_api_key.result
}

resource "aws_cloudwatch_event_bus" "audit" {
  name = "${local.name_prefix}-audit"
  tags = local.common_tags
}

resource "aws_sqs_queue" "audit" {
  name                       = "${local.name_prefix}-audit-ingest"
  message_retention_seconds  = 1209600
  visibility_timeout_seconds = 60
  kms_master_key_id          = aws_kms_key.main.arn

  tags = local.common_tags
}

resource "aws_cloudwatch_event_rule" "audit_to_sqs" {
  name           = "${local.name_prefix}-audit-to-sqs"
  event_bus_name = aws_cloudwatch_event_bus.audit.name
  event_pattern = jsonencode({
    account = [local.account_id]
  })
}

resource "aws_cloudwatch_event_target" "audit_sqs" {
  rule           = aws_cloudwatch_event_rule.audit_to_sqs.name
  event_bus_name = aws_cloudwatch_event_bus.audit.name
  arn            = aws_sqs_queue.audit.arn
}

resource "aws_sqs_queue_policy" "audit" {
  queue_url = aws_sqs_queue.audit.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = aws_sqs_queue.audit.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.audit_to_sqs.arn }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "audit_sqs_core" {
  name = "${local.name_prefix}-audit-sqs"
  role = aws_iam_role.ec2_core.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ChangeMessageVisibility"]
        Resource = aws_sqs_queue.audit.arn
      },
    ]
  })
}
