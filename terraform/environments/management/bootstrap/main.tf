# Dev·Prod와 같은 state-bucket module로 Management State Bucket과 State key를 만든다.
module "state_bucket" {
  source = "../../../modules/state-bucket"

  bucket_name   = "cloud-platform-management-tfstate-${local.account_id}" # 예: cloud-platform-management-tfstate-000000000000
  account_label = "management"                                            # alias/cloud-platform-management-tfstate

  # State를 읽을 수 있는 principal: Management CI Role, OrganizationAdministrator(JIT·bootstrap), break-glass user
  state_reader_principal_arns = [
    "arn:aws:iam::${local.account_id}:role/gha-management-*",
    "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_OrganizationAdministrator_*",
    "arn:aws:iam::${local.account_id}:user/break-glass/*",
  ]
}