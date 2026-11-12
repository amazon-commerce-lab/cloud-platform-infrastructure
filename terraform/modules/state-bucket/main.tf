# Terraform State를 저장하는 S3 버킷과 State 전용 KMS key.
# 버전 관리, SSE-KMS(전용 key), 공개 차단, 소유권 고정, TLS 강제, 허용 목록 밖 principal의 읽기 거부를 기본으로 켠다.

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id # 이 Bucket을 만드는 Account
  # key 사용 권한 없이 할 수 있는 관리 action. Encrypt·Decrypt는 넣지 않는다.
  key_admin_actions = [
    "kms:Create*", "kms:Describe*", "kms:Enable*", "kms:List*", "kms:Put*", "kms:Update*",
    "kms:Revoke*", "kms:Disable*", "kms:Get*", "kms:Delete*", "kms:TagResource", "kms:UntagResource",
    "kms:ScheduleKeyDeletion", "kms:CancelKeyDeletion", "kms:RotateKeyOnDemand"
  ]
}

# State 전용 CMK. 복호화는 state_reader_principal_arns만 할 수 있다.
resource "aws_kms_key" "state" {
  description             = "Terraform State ${var.account_label}" # 콘솔에서 구분하는 설명
  enable_key_rotation     = true                                   # 매년 자동 rotation
  deletion_window_in_days = 30                                     # 삭제 예약 뒤 30일 동안 취소 가능

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Account IAM이 key 관리 action을 위임받는다. 실제 관리 제한은 SCP ProtectStateKeys가 맡는다.
        Sid       = "KeyAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = local.key_admin_actions
        Resource  = "*"
      },
      {
        # State 암호화·복호화는 허용한 principal만. 예: gha-* CI Role, break-glass Role
        Sid       = "StateDataAccess"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${local.account_id}:root" }
        Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
        Resource  = "*"
        Condition = { ArnLike = { "aws:PrincipalArn" = var.state_reader_principal_arns } }
      }
    ]
  })

  lifecycle {
    prevent_destroy = true # key를 지우면 State를 영영 읽지 못한다
  }
}

# init의 kms_key_id와 SCP(kms:ResourceAliases)가 이 이름으로 key를 찾는다.
resource "aws_kms_alias" "state" {
  name          = "alias/cloud-platform-${var.account_label}-tfstate" # 예: alias/cloud-platform-dev-tfstate
  target_key_id = aws_kms_key.state.key_id
}

# State Bucket.
resource "aws_s3_bucket" "state" {
  bucket = var.bucket_name # 예: cloud-platform-dev-tfstate-000000000000

  lifecycle {
    prevent_destroy = true # 실수로 destroy해도 Bucket은 남긴다
  }
}

# 덮어쓴 State를 되돌릴 수 있게 versioning을 켠다.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled" # 한 번 켜면 Suspended로만 바꿀 수 있다
  }
}

# 저장되는 객체를 State 전용 key로 암호화한다.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"             # SSE-KMS
      kms_master_key_id = aws_kms_key.state.arn # 위 전용 key
    }
    bucket_key_enabled = true # KMS 요청 수(비용)를 줄인다
  }
}

# 공개 ACL·공개 policy를 4가지 설정으로 모두 막는다.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true # 새 공개 ACL 거부
  block_public_policy     = true # 공개 Bucket policy 거부
  ignore_public_acls      = true # 기존 공개 ACL 무시
  restrict_public_buckets = true # 공개 policy가 있어도 교차 Account 접근 제한
}

# 소유권을 Bucket 소유자로 고정해 ACL을 끈다.
resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced" # ACL 비활성화
  }
}

# HTTPS가 아닌 요청과 허용 목록 밖 principal의 State 읽기를 거부하는 Bucket Policy.
resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport" # TLS가 아닌 요청 거부
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        # Account 관리자라도 목록 밖 principal은 State·저장 plan을 읽지 못한다.
        Sid       = "DenyStateReadOutsideReaders"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource  = "${aws_s3_bucket.state.arn}/*"
        Condition = { ArnNotLike = { "aws:PrincipalArn" = var.state_reader_principal_arns } }
      }
    ]
  })

  # Public Access Block이 먼저 적용된 뒤 policy를 붙인다.
  depends_on = [aws_s3_bucket_public_access_block.state]
}

# 승인 대기 중인 plan 파일은 오래 둘 이유가 없으므로 7일 뒤 지운다.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-saved-plans" # 저장 plan만 대상
    status = "Enabled"

    filter {
      prefix = "plans/" # terraform-stack.yml save-plan이 쓰는 경로
    }

    expiration {
      days = 7 # 승인 기한보다 길게
    }

    noncurrent_version_expiration {
      noncurrent_days = 1 # 이전 버전은 하루 뒤 삭제
    }
  }

  # versioning이 켜진 뒤 lifecycle을 건다.
  depends_on = [aws_s3_bucket_versioning.state]
}