# Desk-hours ops alerts. Emails from var.ops_alert_emails (empty = no subscribers).

resource "aws_sns_topic" "ops" {
  name = "${local.name_prefix}-ops"
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ops" })
}

resource "aws_sns_topic_policy" "ops" {
  arn = aws_sns_topic.ops.arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudWatchAlarms"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.ops.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account_id }
        }
      },
    ]
  })
}

resource "aws_sns_topic_subscription" "ops_email" {
  for_each  = toset(var.ops_alert_emails)
  topic_arn = aws_sns_topic.ops.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  alarm_name          = "${local.name_prefix}-alb-target-5xx"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 20
  treat_missing_data  = "notBreaching"
  alarm_description   = "ALB targets returned >= 20 5xx in 5 minutes"
  alarm_actions       = [aws_sns_topic.ops.arn]
  ok_actions          = [aws_sns_topic.ops.arn]

  dimensions = {
    LoadBalancer = aws_lb.api.arn_suffix
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "tg_unhealthy" {
  for_each = {
    identity = aws_lb_target_group.identity.arn_suffix
    crm_api  = aws_lb_target_group.crm_api.arn_suffix
    client   = aws_lb_target_group.client.arn_suffix
  }

  alarm_name          = "${local.name_prefix}-unhealthy-${each.key}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_description   = "Target group ${each.key} has an unhealthy host"
  alarm_actions       = [aws_sns_topic.ops.arn]
  ok_actions          = [aws_sns_topic.ops.arn]

  dimensions = {
    LoadBalancer = aws_lb.api.arn_suffix
    TargetGroup  = each.value
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  for_each = {
    core    = aws_db_instance.core.identifier
    trading = aws_db_instance.trading.identifier
  }

  alarm_name          = "${local.name_prefix}-rds-cpu-${each.key}"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_description   = "RDS ${each.key} CPU >= 80% for 10 minutes"
  alarm_actions       = [aws_sns_topic.ops.arn]
  ok_actions          = [aws_sns_topic.ops.arn]

  dimensions = {
    DBInstanceIdentifier = each.value
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  for_each = {
    core    = aws_db_instance.core.identifier
    trading = aws_db_instance.trading.identifier
  }

  alarm_name          = "${local.name_prefix}-rds-storage-${each.key}"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120
  treat_missing_data  = "breaching"
  alarm_description   = "RDS ${each.key} free storage < 5 GiB"
  alarm_actions       = [aws_sns_topic.ops.arn]
  ok_actions          = [aws_sns_topic.ops.arn]

  dimensions = {
    DBInstanceIdentifier = each.value
  }

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "audit_dlq" {
  alarm_name          = "${local.name_prefix}-audit-dlq-depth"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  alarm_description   = "Audit ingest DLQ has a message (poison or repeated persist fail)"
  alarm_actions       = [aws_sns_topic.ops.arn]
  ok_actions          = [aws_sns_topic.ops.arn]

  dimensions = {
    QueueName = aws_sqs_queue.audit_dlq.name
  }

  tags = local.common_tags
}
