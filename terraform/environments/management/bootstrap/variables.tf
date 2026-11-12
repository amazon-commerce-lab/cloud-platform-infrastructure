# Account 짧은 이름 → Account ID. 커밋하지 않는다.
#   CI: terraform-stack.yml이 repository 변수 ACCOUNT_IDS(GitHub stack이 Organizations에서 만든 값)를 TF_VAR_account_ids로 넣는다.
#   로컬 bootstrap: make bootstrap 이 aws organizations list-accounts 결과로 TF_VAR_account_ids를 만든다.
variable "account_ids" {
  description = "Account 짧은 이름 → Account ID."
  type        = map(string) # 예: { management = "999999999999", network = "666666666666", dev = "111111111111", prod = "222222222222", security = "333333333333", log-archive = "444444444444", backup = "555555555555" }

  validation {
    condition     = alltrue([for key in ["management", "network", "dev", "prod", "security", "log-archive", "backup"] : can(regex("^[0-9]{12}$", var.account_ids[key]))])
    error_message = "management, network, dev, prod, security, log-archive, backup 일곱 Account ID가 모두 필요합니다."
  }
}

# provider가 쓸 기본 Region. terraform.tfvars에서 넣는다.
variable "region" {
  type = string # 예: ap-northeast-2
}