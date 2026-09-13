terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  required_version = ">= 1.5.0"
}

provider "aws" {
  region = "us-east-1"

  access_key = "test"
  secret_key = "test"

  endpoints {
    eks = "http://floci:4566"//localhost sẽ bị lỗi khi chay trong jenkins
    iam = "http://floci:4566"//localhost sẽ bị lỗi khi chay trong jenkins
  }

  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}