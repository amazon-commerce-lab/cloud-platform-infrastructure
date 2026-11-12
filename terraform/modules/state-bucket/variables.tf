# module 입력 값: Bucket 이름, key alias에 넣을 Account 이름, State를 읽을 수 있는 principal.
variable "bucket_name" {
  description = "State 버킷 이름. 전 세계에서 유일해야 한다."
  type        = string # 예: cloud-platform-dev-tfstate-000000000000
}

variable "account_label" {
  description = "KMS alias에 넣는 Account 짧은 이름(management, network, dev, prod, security, log-archive, backup)."
  type        = string # 예: dev → alias/cloud-platform-dev-tfstate

  validation {
    condition     = can(regex("^[a-z][a-z-]{1,20}$", var.account_label))
    error_message = "소문자와 -만 씁니다. 예: dev, log-archive"
  }
}

variable "state_reader_principal_arns" {
  description = "State object를 읽고 State key로 복호화할 수 있는 IAM principal ARN 패턴. 이 목록 밖 principal의 GetObject는 Bucket policy가 거부한다."
  type        = list(string) # 예: ["arn:aws:iam::000000000000:role/gha-*", "arn:aws:iam::000000000000:role/break-glass/commerce-break-glass"]

  validation {
    condition     = length(var.state_reader_principal_arns) > 0
    error_message = "읽을 수 있는 principal이 하나도 없으면 아무도 State를 읽지 못합니다."
  }
}
