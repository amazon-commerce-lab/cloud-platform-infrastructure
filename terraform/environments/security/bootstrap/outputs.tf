# apply 뒤 terraform output으로 읽는 값.
output "state_bucket_name" {
  value = module.state_bucket.bucket_name # init -backend-config의 bucket
}

output "state_kms_key_arn" {
  value = module.state_bucket.kms_key_arn # init -backend-config의 kms_key_id
}