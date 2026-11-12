# 실제로 실행하는 stack이므로 버전을 정확히 고정한다.
terraform {
  required_version = "= 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 6.62.0"
    }
  }
}