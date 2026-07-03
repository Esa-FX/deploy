data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_core" {
  name               = "${local.name_prefix}-ec2-core-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role" "ec2_crm" {
  name               = "${local.name_prefix}-ec2-crm-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role" "ec2_voip" {
  name               = "${local.name_prefix}-ec2-voip-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role" "ec2_mt" {
  name               = "${local.name_prefix}-ec2-mt-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_core.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ssm_crm" {
  role       = aws_iam_role.ec2_crm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ssm_voip" {
  role       = aws_iam_role.ec2_voip.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ssm_mt" {
  role       = aws_iam_role.ec2_mt.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "core" {
  name = "${local.name_prefix}-ec2-core-profile"
  role = aws_iam_role.ec2_core.name
}

resource "aws_iam_instance_profile" "crm" {
  name = "${local.name_prefix}-ec2-crm-profile"
  role = aws_iam_role.ec2_crm.name
}

resource "aws_iam_instance_profile" "voip" {
  name = "${local.name_prefix}-ec2-voip-profile"
  role = aws_iam_role.ec2_voip.name
}

resource "aws_iam_instance_profile" "mt" {
  name = "${local.name_prefix}-ec2-mt-profile"
  role = aws_iam_role.ec2_mt.name
}

data "aws_iam_policy_document" "secrets_read" {
  statement {
    sid    = "ReadProductionSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]
    resources = ["arn:aws:secretsmanager:${var.aws_region}:${local.account_id}:secret:${var.project}/${var.environment}/*"]
  }
}

resource "aws_iam_role_policy" "secrets_core" {
  name   = "${local.name_prefix}-secrets-read"
  role   = aws_iam_role.ec2_core.id
  policy = data.aws_iam_policy_document.secrets_read.json
}

resource "aws_iam_role_policy" "secrets_crm" {
  name   = "${local.name_prefix}-secrets-read"
  role   = aws_iam_role.ec2_crm.id
  policy = data.aws_iam_policy_document.secrets_read.json
}

resource "aws_iam_role_policy" "secrets_voip" {
  name   = "${local.name_prefix}-secrets-read"
  role   = aws_iam_role.ec2_voip.id
  policy = data.aws_iam_policy_document.secrets_read.json
}

resource "aws_iam_role_policy" "secrets_mt" {
  name   = "${local.name_prefix}-secrets-read"
  role   = aws_iam_role.ec2_mt.id
  policy = data.aws_iam_policy_document.secrets_read.json
}

resource "aws_iam_role_policy" "call_recordings_voip" {
  name = "${local.name_prefix}-call-recordings-s3"
  role = aws_iam_role.ec2_voip.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:AbortMultipartUpload"]
        Resource = "${aws_s3_bucket.call_recordings.arn}/${local.recordings_prefix}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.call_recordings.arn
        Condition = {
          StringLike = { "s3:prefix" = ["${local.recordings_prefix}/*"] }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "call_recordings_crm" {
  name = "${local.name_prefix}-call-recordings-s3-read"
  role = aws_iam_role.ec2_crm.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.call_recordings.arn}/${local.recordings_prefix}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.call_recordings.arn
        Condition = {
          StringLike = { "s3:prefix" = ["${local.recordings_prefix}/*"] }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "ftd_uploads_crm" {
  name = "${local.name_prefix}-ftd-uploads-s3"
  role = aws_iam_role.ec2_crm.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:AbortMultipartUpload"]
        Resource = "${aws_s3_bucket.ftd_uploads.arn}/${local.ftd_uploads_prefix}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.ftd_uploads.arn
        Condition = {
          StringLike = { "s3:prefix" = ["${local.ftd_uploads_prefix}/*"] }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "client_docs_crm" {
  name = "${local.name_prefix}-client-docs-s3"
  role = aws_iam_role.ec2_crm.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
        Resource = [
          "${aws_s3_bucket.kyc_docs.arn}/*",
          "${aws_s3_bucket.signed_agreements.arn}/*",
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.kyc_docs.arn, aws_s3_bucket.signed_agreements.arn]
      },
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_crm" {
  name = "${local.name_prefix}-eventbridge-publish"
  role = aws_iam_role.ec2_crm.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = aws_cloudwatch_event_bus.audit.arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_core" {
  name = "${local.name_prefix}-eventbridge-publish"
  role = aws_iam_role.ec2_core.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["events:PutEvents"]
        Resource = aws_cloudwatch_event_bus.audit.arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "kms_core" {
  name = "${local.name_prefix}-kms-pii"
  role = aws_iam_role.ec2_core.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
        ]
        Resource = aws_kms_key.main.arn
      },
    ]
  })
}

resource "aws_iam_role_policy" "cognito_staff_admin_core" {
  name = "${local.name_prefix}-cognito-staff-admin"
  role = aws_iam_role.ec2_core.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminSetUserPassword",
          "cognito-idp:AdminUpdateUserAttributes",
          "cognito-idp:AdminGetUser",
          "cognito-idp:AdminDisableUser",
          "cognito-idp:AdminEnableUser",
        ]
        Resource = aws_cognito_user_pool.staff.arn
      },
    ]
  })
}
