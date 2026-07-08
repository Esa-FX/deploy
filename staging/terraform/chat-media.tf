locals {
  chat_media_bucket_name = "esafx-${var.environment}-chat-media-${local.account_id}"
  chat_media_prefix      = "chat-media"
}

resource "aws_s3_bucket" "chat_media" {
  bucket = local.chat_media_bucket_name

  tags = {
    Name        = local.chat_media_bucket_name
    Environment = var.environment
    Service     = "whatsapp-chat-media"
    ManagedBy   = "terraform"
  }
}

resource "aws_s3_bucket_public_access_block" "chat_media" {
  bucket = aws_s3_bucket.chat_media.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "chat_media" {
  bucket = aws_s3_bucket.chat_media.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "chat_media" {
  bucket = aws_s3_bucket.chat_media.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role_policy" "chat_media_app_ec2" {
  name = "esafx-${var.environment}-chat-media-s3"
  role = data.aws_iam_role.app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "WhatsAppGatewayPutChatMedia"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:AbortMultipartUpload",
        ]
        Resource = "${aws_s3_bucket.chat_media.arn}/${local.chat_media_prefix}/*"
      },
      {
        Sid    = "WhatsAppGatewayGetChatMedia"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
        ]
        Resource = "${aws_s3_bucket.chat_media.arn}/${local.chat_media_prefix}/*"
      },
      {
        Sid    = "CrmApiGetChatMedia"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
        ]
        Resource = "${aws_s3_bucket.chat_media.arn}/${local.chat_media_prefix}/*"
      },
      {
        Sid    = "ListChatMediaPrefix"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
        ]
        Resource = aws_s3_bucket.chat_media.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["${local.chat_media_prefix}/*"]
          }
        }
      },
    ]
  })
}
