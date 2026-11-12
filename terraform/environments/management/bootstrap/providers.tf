# Management Account에만 적용되도록 provider를 설정한다.
provider "aws" {
  region              = var.region
  allowed_account_ids = [var.account_ids["management"]]

  # 이 stack의 모든 resource에 붙는 tag
  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Stack     = "management/bootstrap"
    }
  }
}