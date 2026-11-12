#!/usr/bin/env bash
# bootstrap stack의 로컬 State를 그 Account의 State Bucket으로 옮긴다(02-04). 옮긴 뒤 plan에 변경이 없어야 로컬 사본을 지운다.
# 사용: scripts/ops/migrate-state.sh <management|network|dev|prod|security|log-archive|backup>
#   Bucket: cloud-platform-<account>-tfstate-<Account ID>, key: alias/cloud-platform-<account>-tfstate
#   이관 전 로컬 State 사본: ~/commerce-admin/work/records/<account>-bootstrap.tfstate.pre-migrate
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -ne 1 ]; then
  echo "사용: $0 <management|network|dev|prod|security|log-archive|backup>" >&2
  exit 2
fi
account="$1"
[ "$account" != github ] || fail "github stack은 처음부터 Management State Bucket을 씁니다. 이관할 로컬 State가 없습니다."
profile=$(bootstrap_profile "$account")
stack_dir="$(infra_root)/terraform/environments/$account/bootstrap"
records_dir="$HOME/commerce-admin/work/records"
local_state="$stack_dir/terraform.tfstate"

[ -f "$local_state" ] || fail "로컬 State가 없습니다: $local_state (이미 이관했으면 make validate·plan으로 확인합니다)"
grep -q 'backend "s3"' "$stack_dir"/*.tf || fail "${stack_dir}에 backend \"s3\" 블록이 없습니다. backend.tf를 먼저 commit합니다."

export AWS_PROFILE="$profile"
export_bootstrap_inputs
account_id=$(aws sts get-caller-identity --query Account --output text)

# 이관이 잘못되면 이 사본으로 되돌린다. 이미 있으면 덮어쓰지 않는다.
mkdir -p "$records_dir"
cp -n "$local_state" "$records_dir/$account-bootstrap.tfstate.pre-migrate"

# -force-copy: "기존 State를 새 backend로 복사할까요?" 질문에 yes로 답한다.
terraform -chdir="$stack_dir" init -input=false -migrate-state -force-copy \
  -backend-config="bucket=cloud-platform-$account-tfstate-$account_id" \
  -backend-config="kms_key_id=alias/cloud-platform-$account-tfstate"

# 같은 코드로 plan을 다시 본다. 변경이 있으면(exit 2) 여기서 멈추고 로컬 사본을 남긴다.
terraform -chdir="$stack_dir" plan -input=false -detailed-exitcode

# Bucket이 원본이 됐으므로 작업 폴더의 로컬 State를 지운다. 되돌릴 사본은 records에 있다.
rm -f "$local_state" "$local_state.backup"
note "이관 완료: s3://cloud-platform-$account-tfstate-$account_id/bootstrap/terraform.tfstate"
