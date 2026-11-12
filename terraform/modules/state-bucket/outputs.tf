# stack이 module.state_bucket.<이름>으로 읽는 값.
output "bucket_name" {
  value = aws_s3_bucket.state.id # init -backend-config의 bucket 값
}

output "bucket_arn" {
  value = aws_s3_bucket.state.arn # CI Role 권한의 Resource
}

# init -backend-config의 kms_key_id 값과 CI Role의 kms 권한 Resource.
output "kms_key_arn" {
  value = aws_kms_key.state.arn
}

output "kms_alias_name" {
  value = aws_kms_alias.state.name # 예: alias/cloud-platform-dev-tfstate
}