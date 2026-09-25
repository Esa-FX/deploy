resource "aws_cognito_user_pool" "staff" {
  name = "${local.name_prefix}-staff"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  password_policy {
    minimum_length                   = 10
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = false
    require_uppercase                = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  user_attribute_update_settings {
    attributes_require_verification_before_update = ["email"]
  }

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
  }

  schema {
    name                     = "role"
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    required                 = false

    string_attribute_constraints {
      min_length = 1
      max_length = 64
    }
  }

  schema {
    name                     = "display_name"
    attribute_data_type      = "String"
    developer_only_attribute = false
    mutable                  = true
    required                 = false

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  tags = local.common_tags
}

resource "aws_cognito_user_pool_client" "crm_spa" {
  name         = "${local.name_prefix}-crm-spa"
  user_pool_id = aws_cognito_user_pool.staff.id

  generate_secret = false

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = var.cognito_callback_urls
  logout_urls   = var.cognito_logout_urls

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
  ]

  prevent_user_existence_errors = "ENABLED"

  access_token_validity  = 60
  id_token_validity      = 60
  refresh_token_validity = 30

  token_validity_units {
    access_token  = "minutes"
    id_token      = "minutes"
    refresh_token = "days"
  }

  write_attributes = [
    "address",
    "birthdate",
    "email",
    "family_name",
    "gender",
    "given_name",
    "locale",
    "middle_name",
    "name",
    "nickname",
    "picture",
    "preferred_username",
    "profile",
    "updated_at",
    "website",
    "zoneinfo",
  ]
}

resource "aws_cognito_user_pool_client" "wiki_alb" {
  name         = "esafx-wiki-alb"
  user_pool_id = aws_cognito_user_pool.staff.id

  generate_secret = true

  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code"]
  allowed_oauth_scopes                 = ["openid"]

  callback_urls = ["https://wiki.esandardev.com/oauth2/idpresponse"]
  logout_urls   = ["https://wiki.esandardev.com/"]

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = ["ALLOW_REFRESH_TOKEN_AUTH"]

  read_attributes  = ["email", "email_verified"]
  write_attributes = ["email", "name"]
}

data "aws_cognito_user_pool_clients" "staff" {
  user_pool_id = aws_cognito_user_pool.staff.id
}

locals {
  wiki_alb_client_index = index(data.aws_cognito_user_pool_clients.staff.client_names, "esafx-wiki-alb")
}

# Adopts the existing pool client by id resolved from the pool at plan time. Keep this import so a new state does not create a second client.
import {
  to = aws_cognito_user_pool_client.wiki_alb
  id = "${aws_cognito_user_pool.staff.id}/${data.aws_cognito_user_pool_clients.staff.client_ids[local.wiki_alb_client_index]}"
}

resource "aws_cognito_user_pool_domain" "staff" {
  domain       = "${var.project}-${var.environment}-esandardev"
  user_pool_id = aws_cognito_user_pool.staff.id
}
