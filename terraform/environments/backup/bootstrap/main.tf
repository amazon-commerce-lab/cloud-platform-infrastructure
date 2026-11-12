# Backup Account bootstrap: State Bucket·key, CI Role, 비상 Role, Account 기준선, 보안 event 전달.
# 첫 apply만 로컬(InfrastructureProvisioner bootstrap 배정)로 하고 실행 기록·사후 PR을 남긴다. 이후 변경은 admin lane CI만.

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id # 이 Account ID. 예: 111111111111

  # State를 읽을 수 있는 principal: 이 Account의 CI Role, 비상 Role, InfrastructureProvisioner(추후 JIT로만 받음)
  state_readers = [
    "arn:aws:iam::${local.account_id}:role/gha-*",
    "arn:aws:iam::${local.account_id}:role/break-glass/commerce-break-glass",
    "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_InfrastructureProvisioner_*",
  ]
}

# State Bucket과 State 전용 key(alias/cloud-platform-backup-tfstate).
module "state_bucket" {
  source = "../../../modules/state-bucket"

  bucket_name                 = "cloud-platform-${var.environment}-tfstate-${local.account_id}" # 예: cloud-platform-backup-tfstate-000000000000
  account_label               = var.environment
  state_reader_principal_arns = local.state_readers
}