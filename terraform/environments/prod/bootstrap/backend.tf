# 처음 apply는 이 파일 없이(로컬 State) 실행하고, State 버킷이 생긴 뒤 추가해 이관한다.
# bucket·kms_key_id는 init 때 넘긴다. 로컬 이관은 make migrate-state ACCOUNT=<acct>, CI는 terraform-stack.yml이
# -backend-config="bucket=cloud-platform-<acct>-tfstate-<ID>" -backend-config="kms_key_id=alias/cloud-platform-<acct>-tfstate"로 넘긴다.
terraform {
  backend "s3" {
    key          = "bootstrap/terraform.tfstate" # 이 stack의 State 경로
    region       = "ap-northeast-2"
    encrypt      = true # SSE-KMS(init의 kms_key_id)
    use_lockfile = true # S3 lock 파일(.tflock)
  }
}