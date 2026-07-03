resource "aws_s3_bucket" "call_recordings" {
  bucket = local.call_recordings_bucket
  tags   = merge(local.common_tags, { Service = "call-recordings" })
}

resource "aws_s3_bucket_public_access_block" "call_recordings" {
  bucket                  = aws_s3_bucket.call_recordings.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "call_recordings" {
  bucket = aws_s3_bucket.call_recordings.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "call_recordings" {
  bucket = aws_s3_bucket.call_recordings.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket" "ftd_uploads" {
  bucket = local.ftd_uploads_bucket
  tags   = merge(local.common_tags, { Service = "ftd-uploads" })
}

resource "aws_s3_bucket_public_access_block" "ftd_uploads" {
  bucket                  = aws_s3_bucket.ftd_uploads.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "ftd_uploads" {
  bucket = aws_s3_bucket.ftd_uploads.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "ftd_uploads" {
  bucket = aws_s3_bucket.ftd_uploads.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket" "crm_frontend" {
  bucket = local.crm_frontend_bucket
  tags   = merge(local.common_tags, { Service = "crm-frontend" })
}

resource "aws_s3_bucket_public_access_block" "crm_frontend" {
  bucket                  = aws_s3_bucket.crm_frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "crm_frontend" {
  bucket = aws_s3_bucket.crm_frontend.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_cloudfront_origin_access_control" "crm" {
  name                              = "${local.name_prefix}-crm-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "crm_frontend_oac" {
  statement {
    sid    = "AllowCloudFrontRead"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.crm_frontend.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.crm.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "crm_frontend" {
  bucket = aws_s3_bucket.crm_frontend.id
  policy = data.aws_iam_policy_document.crm_frontend_oac.json
}

resource "aws_s3_bucket" "kyc_docs" {
  bucket = local.kyc_docs_bucket
  tags   = merge(local.common_tags, { Service = "kyc-docs" })
}

resource "aws_s3_bucket_public_access_block" "kyc_docs" {
  bucket                  = aws_s3_bucket.kyc_docs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "kyc_docs" {
  bucket = aws_s3_bucket.kyc_docs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "signed_agreements" {
  bucket = local.agreements_bucket
  tags   = merge(local.common_tags, { Service = "signed-agreements" })
}

resource "aws_s3_bucket_public_access_block" "signed_agreements" {
  bucket                  = aws_s3_bucket.signed_agreements.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "signed_agreements" {
  bucket = aws_s3_bucket.signed_agreements.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}
