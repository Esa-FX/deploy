terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
  }
}

locals {
  metric = replace(var.name, "/[^A-Za-z0-9]/", "")
}

# Cognito forwards x-amzn-cognito-operation-name for public API calls (Amplify / SDK).
# Hosted UI / managed login has no request body; CAPTCHA actions are not used — custom
# login UIs get ForbiddenException and cannot render an AWS WAF puzzle.
resource "aws_wafv2_web_acl" "cognito" {
  name        = var.name
  description = "Rate limits and IP reputation for Cognito login DoS protection."
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "ip-reputation"
    priority = 0

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric}IpRep"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-global"
    priority = 10

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = var.rate_limit_global
        aggregate_key_type    = "CONSTANT"
        evaluation_window_sec = var.evaluation_window_sec

        # CONSTANT aggregation requires a scope-down. Host always includes "amazon"
        # for cognito-idp.*.amazonaws.com and *.amazoncognito.com.
        scope_down_statement {
          byte_match_statement {
            positional_constraint = "CONTAINS"
            search_string         = "amazon"
            field_to_match {
              single_header {
                name = "host"
              }
            }
            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric}RateGlobal"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-per-ip"
    priority = 20

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = var.rate_limit_per_ip
        aggregate_key_type    = "IP"
        evaluation_window_sec = var.evaluation_window_sec
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric}RateIp"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "rate-sensitive-auth"
    priority = 30

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = var.rate_limit_sensitive_per_ip
        aggregate_key_type    = "IP"
        evaluation_window_sec = var.evaluation_window_sec

        scope_down_statement {
          or_statement {
            statement {
              byte_match_statement {
                positional_constraint = "EXACTLY"
                search_string         = "ForgotPassword"
                field_to_match {
                  single_header {
                    name = "x-amzn-cognito-operation-name"
                  }
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
            statement {
              byte_match_statement {
                positional_constraint = "EXACTLY"
                search_string         = "ConfirmForgotPassword"
                field_to_match {
                  single_header {
                    name = "x-amzn-cognito-operation-name"
                  }
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
            statement {
              byte_match_statement {
                positional_constraint = "EXACTLY"
                search_string         = "SignUp"
                field_to_match {
                  single_header {
                    name = "x-amzn-cognito-operation-name"
                  }
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
            statement {
              byte_match_statement {
                positional_constraint = "EXACTLY"
                search_string         = "ResendConfirmationCode"
                field_to_match {
                  single_header {
                    name = "x-amzn-cognito-operation-name"
                  }
                }
                text_transformation {
                  priority = 0
                  type     = "NONE"
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.metric}RateSensitive"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = local.metric
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

resource "aws_wafv2_web_acl_association" "cognito" {
  for_each = toset(var.user_pool_arns)

  resource_arn = each.value
  web_acl_arn  = aws_wafv2_web_acl.cognito.arn
}
