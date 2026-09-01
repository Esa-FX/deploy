# ALB WAF — Count mode only. Do not flip to Block without reviewing sampled logs.
# No IP rate-based rule (office NAT + Zapier shared egress).

resource "aws_wafv2_web_acl" "api" {
  name  = "${local.name_prefix}-api"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  dynamic "rule" {
    for_each = {
      10 = "AWSManagedRulesAmazonIpReputationList"
      20 = "AWSManagedRulesKnownBadInputsRuleSet"
      30 = "AWSManagedRulesSQLiRuleSet"
      40 = "AWSManagedRulesCommonRuleSet"
    }
    content {
      name     = rule.value
      priority = tonumber(rule.key)

      override_action {
        count {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.value
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = replace(rule.value, "AWSManagedRules", "")
        sampled_requests_enabled   = true
      }
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${replace(local.name_prefix, "-", "")}ApiWaf"
    sampled_requests_enabled   = true
  }

  tags = local.common_tags
}

resource "aws_wafv2_web_acl_association" "api" {
  resource_arn = aws_lb.api.arn
  web_acl_arn  = aws_wafv2_web_acl.api.arn
}
