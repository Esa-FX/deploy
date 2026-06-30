data "aws_caller_identity" "current" {}

locals {
  account_id   = data.aws_caller_identity.current.account_id
  bucket_name  = "esafx-${var.environment}-call-recordings-${local.account_id}"
  recordings_prefix = "recordings"
}

resource "aws_s3_bucket" "call_recordings" {
  bucket = local.bucket_name

  tags = {
    Name        = local.bucket_name
    Environment = var.environment
    Service     = "call-recordings"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "call_recordings" {
  bucket = aws_s3_bucket.call_recordings.id

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

  versioning_configuration {
    status = "Enabled"
  }
}

data "aws_iam_role" "app_ec2" {
  name = var.app_ec2_role_name
}

resource "aws_iam_role_policy" "call_recordings_app_ec2" {
  name = "esafx-${var.environment}-call-recordings-s3"
  role = data.aws_iam_role.app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "VoipGatewayPutRecordings"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:AbortMultipartUpload",
        ]
        Resource = "${aws_s3_bucket.call_recordings.arn}/${local.recordings_prefix}/*"
      },
      {
        Sid    = "CrmApiGetRecordings"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
        ]
        Resource = "${aws_s3_bucket.call_recordings.arn}/${local.recordings_prefix}/*"
      },
      {
        Sid    = "ListBucketPrefix"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = aws_s3_bucket.call_recordings.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["${local.recordings_prefix}/*"]
          }
        }
      },
    ]
  })
}
