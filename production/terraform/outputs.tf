output "vpc_id" {
  value = aws_vpc.main.id
}

output "core_ec2_instance_id" {
  value = aws_instance.core.id
}

output "core_ec2_private_ip" {
  value = aws_instance.core.private_ip
}

output "crm_ec2_instance_id" {
  value = aws_instance.crm.id
}

output "crm_ec2_private_ip" {
  value = aws_instance.crm.private_ip
}

output "voip_ec2_instance_id" {
  value = aws_instance.voip.id
}

output "voip_ec2_private_ip" {
  value = aws_instance.voip.private_ip
}

output "voip_elastic_ip" {
  description = "Stable public IP for VoIP vendor whitelisting (AMI/SIP outbound source)"
  value       = aws_eip.voip.public_ip
}

output "mt_ec2_instance_id" {
  value = aws_instance.mt.id
}

output "mt_ec2_private_ip" {
  value = aws_instance.mt.private_ip
}

output "rds_core_endpoint" {
  value = aws_db_instance.core.address
}

output "rds_core_port" {
  value = aws_db_instance.core.port
}

output "rds_trading_endpoint" {
  value = aws_db_instance.trading.address
}

output "rds_trading_port" {
  value = aws_db_instance.trading.port
}

output "redis_endpoint" {
  value = aws_elasticache_cluster.redis.cache_nodes[0].address
}

output "redis_port" {
  value = aws_elasticache_cluster.redis.port
}

output "alb_dns_name" {
  value = aws_lb.api.dns_name
}

output "api_url" {
  value = "https://${var.api_hostname}"
}

output "crm_url" {
  value = "https://${var.crm_hostname}"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.staff.id
}

output "cognito_app_client_id" {
  value = aws_cognito_user_pool_client.crm_spa.id
}

output "cognito_domain" {
  value = "${aws_cognito_user_pool_domain.staff.domain}.auth.${var.aws_region}.amazoncognito.com"
}

output "crm_frontend_bucket_name" {
  value = aws_s3_bucket.crm_frontend.bucket
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.crm.id
}

output "call_recordings_bucket_name" {
  value = aws_s3_bucket.call_recordings.bucket
}

output "ftd_uploads_bucket_name" {
  value = aws_s3_bucket.ftd_uploads.bucket
}

output "audit_event_bus_name" {
  value = aws_cloudwatch_event_bus.audit.name
}

output "audit_sqs_queue_url" {
  value = aws_sqs_queue.audit.url
}

output "kms_key_arn" {
  value = aws_kms_key.main.arn
}

output "kms_key_alias" {
  value = aws_kms_alias.main.name
}

output "secret_core_db_arn" {
  value = aws_secretsmanager_secret.core_db.arn
}

output "secret_trading_db_arn" {
  value = aws_secretsmanager_secret.trading_db.arn
}

output "secret_trading_readonly_db_arn" {
  value = aws_secretsmanager_secret.trading_readonly_db.arn
}

output "secret_service_tokens_arn" {
  value = aws_secretsmanager_secret.service_tokens.arn
}

output "secret_audit_api_key_arn" {
  value = aws_secretsmanager_secret.audit_api_key.arn
}

output "instance_types" {
  value = {
    linux_ec2   = var.linux_instance_type
    windows_ec2 = var.windows_instance_type
    rds         = var.db_instance_class
    redis       = var.redis_node_type
  }
}
