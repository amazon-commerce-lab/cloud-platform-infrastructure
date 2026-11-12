# 만든 State Bucket 이름과 State key
output "state_bucket_name" {
  value = module.state_bucket.bucket_name
}

output "state_kms_key_arn" {
  value = module.state_bucket.kms_key_arn # init -backend-config의 kms_key_id
}