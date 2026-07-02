data "aws_route53_zone" "main" {
  count        = var.create_route53_records || var.create_acm_certificates ? 1 : 0
  name         = var.domain_name
  private_zone = false
}

resource "aws_acm_certificate" "regional" {
  count = var.create_acm_certificates ? 1 : 0

  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

resource "aws_acm_certificate" "cloudfront" {
  count    = var.create_acm_certificates ? 1 : 0
  provider = aws.us_east_1

  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

resource "aws_route53_record" "acm_regional_validation" {
  for_each = var.create_acm_certificates ? {
    for dvo in aws_acm_certificate.regional[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.main[0].zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

resource "aws_route53_record" "acm_cloudfront_validation" {
  for_each = var.create_acm_certificates ? {
    for dvo in aws_acm_certificate.cloudfront[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.main[0].zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

resource "aws_acm_certificate_validation" "regional" {
  count = var.create_acm_certificates ? 1 : 0

  certificate_arn         = aws_acm_certificate.regional[0].arn
  validation_record_fqdns = [for record in aws_route53_record.acm_regional_validation : record.fqdn]
}

resource "aws_acm_certificate_validation" "cloudfront" {
  count    = var.create_acm_certificates ? 1 : 0
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.cloudfront[0].arn
  validation_record_fqdns = [for record in aws_route53_record.acm_cloudfront_validation : record.fqdn]
}

locals {
  alb_certificate_arn                 = var.create_acm_certificates ? aws_acm_certificate_validation.regional[0].certificate_arn : var.alb_certificate_arn
  cloudfront_certificate_arn_resolved = var.create_acm_certificates ? aws_acm_certificate_validation.cloudfront[0].certificate_arn : var.cloudfront_certificate_arn
}

resource "aws_cloudfront_distribution" "crm" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name_prefix} CRM frontend"
  default_root_object = "index.html"
  aliases             = [var.crm_hostname]
  price_class         = "PriceClass_200"

  origin {
    domain_name              = aws_s3_bucket.crm_frontend.bucket_regional_domain_name
    origin_id                = "crm-s3"
    origin_access_control_id = aws_cloudfront_origin_access_control.crm.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "crm-s3"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = local.cloudfront_certificate_arn_resolved
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = local.common_tags
}

resource "aws_route53_record" "api" {
  count   = var.create_route53_records ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.api_hostname
  type    = "A"

  alias {
    name                   = aws_lb.api.dns_name
    zone_id                = aws_lb.api.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "crm" {
  count   = var.create_route53_records ? 1 : 0
  zone_id = data.aws_route53_zone.main[0].zone_id
  name    = var.crm_hostname
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.crm.domain_name
    zone_id                = aws_cloudfront_distribution.crm.hosted_zone_id
    evaluate_target_health = false
  }
}
