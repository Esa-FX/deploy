locals {
  ftd_uploads_bucket_name = "esafx-${var.environment}-ftd-uploads-${local.account_id}"
  ftd_uploads_prefix      = "ftd"
}

resource "aws_s3_bucket" "ftd_uploads" {
  bucket = local.ftd_uploads_bucket_name

  tags = {
    Name        = local.ftd_uploads_bucket_name
    Environment = var.environment
    Service     = "ftd-uploads"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "ftd_uploads" {
  bucket = aws_s3_bucket.ftd_uploads.id

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

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role_policy" "ftd_uploads_app_ec2" {
  name = "esafx-${var.environment}-ftd-uploads-s3"
  role = data.aws_iam_role.app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CrmApiPutFtdUploads"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:AbortMultipartUpload",
        ]
        Resource = "${aws_s3_bucket.ftd_uploads.arn}/${local.ftd_uploads_prefix}/*"
      },
      {
        Sid    = "CrmApiGetFtdUploads"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
        ]
        Resource = "${aws_s3_bucket.ftd_uploads.arn}/${local.ftd_uploads_prefix}/*"
      },
      {
        Sid    = "ListFtdUploadsPrefix"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = aws_s3_bucket.ftd_uploads.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["${local.ftd_uploads_prefix}/*"]
          }
        }
      },
    ]
  })
}
