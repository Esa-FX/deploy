variable "client_area_user_pool_id" {
  description = "Cognito user pool for my.staging.esandardev.com"
  type        = string
  default     = "ap-southeast-3_pvuDxqsmS"
}

resource "aws_iam_role_policy" "cognito_client_area_app_ec2" {
  name = "esafx-${var.environment}-cognito-client-area"
  role = data.aws_iam_role.app_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CognitoClientAreaAdmin"
        Effect = "Allow"
        Action = [
          "cognito-idp:AdminCreateUser",
          "cognito-idp:AdminSetUserPassword",
          "cognito-idp:AdminUpdateUserAttributes",
          "cognito-idp:AdminGetUser",
        ]
        Resource = "arn:aws:cognito-idp:${var.aws_region}:${data.aws_caller_identity.current.account_id}:userpool/${var.client_area_user_pool_id}"
      },
    ]
  })
}
