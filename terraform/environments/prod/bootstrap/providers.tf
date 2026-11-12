# Prod Account에만 적용되도록 provider를 설정한다.
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_ids[var.environment]] # 다른 Account profile로 실행하면 init 뒤 plan에서 바로 멈춘다

  # 이 stack의 모든 resource에 붙는 tag
  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Stack     = "prod/bootstrap"
    }
  }
}