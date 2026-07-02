terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Uncomment and configure before first apply:
  # backend "s3" {
  #   bucket         = "esafx-terraform-state"
  #   key            = "production/terraform.tfstate"
  #   region         = "ap-southeast-3"
  #   encrypt        = true
  #   dynamodb_table = "esafx-terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}
