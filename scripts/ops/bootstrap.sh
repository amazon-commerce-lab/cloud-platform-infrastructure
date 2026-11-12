#!/usr/bin/env bash
# CI가 생기기 전 bootstrap stack을 로컬에서 plan → 기록 → apply한다(02-02·02-03·02-05·02-12. CI 전이라 로컬 apply를 예외로 둔다).
# 사용: scripts/ops/bootstrap.sh <management|network|dev|prod|security|log-archive|backup|github>
#   stack:   terraform/environments/<account>/bootstrap, github는 terraform/github/settings
#   profile: <account>-bootstrap, management·github는 mgmt-bootstrap-admin
#   기록:    ~/commerce-admin/work/records/bootstrap-<account>.txt (Account ID는 <account>로 가림, PR 본문에 붙임)
# 관리용 container에서 실행한다. 저장한 plan만 apply하므로 화면에서 본 변경만 들어간다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -ne 1 ]; then
  echo "사용: $0 <management|network|dev|prod|security|log-archive|backup|github>" >&2
  exit 2
fi
account="$1"
profile=$(bootstrap_profile "$account")
root_dir=$(infra_root)
records_dir="$HOME/commerce-admin/work/records"
record_file="$records_dir/bootstrap-$account.txt"

if [ "$account" = github ]; then
  stack_dir="$root_dir/terraform/github/settings"
  state_account=management
else
  stack_dir="$root_dir/terraform/environments/$account/bootstrap"
  state_account="$account"
fi
[ -d "$stack_dir" ] || fail "stack 폴더가 없습니다: $stack_dir"

# 이 script 안의 terraform·aws 호출만 이 profile을 쓴다. 터미널의 기본 profile은 바뀌지 않는다.
export AWS_PROFILE="$profile"
export_bootstrap_inputs

# CI Role trust를 만드는 bootstrap(02-06 이후)만 OIDC sub 앞부분 map을 받는다.
# 예: {"cloud-platform-infrastructure":"repo:zoopang-1234@123456789/cloud-platform-infrastructure@987654321",...}
# repository 변수 OIDC_SUBJECT_PREFIXES는 02-05의 GitHub 설정 stack 첫 apply가 만든다.
# 그 전의 State bootstrap(02-02·02-03)과 github stack은 이 변수를 선언하지 않으므로 읽지 않는다.
if grep -q 'variable "github_subject_prefixes"' "$stack_dir"/*.tf; then
  TF_VAR_github_subject_prefixes=$(gh variable get OIDC_SUBJECT_PREFIXES)
  export TF_VAR_github_subject_prefixes
fi

if [ "$account" = github ]; then
  # GitHub stack은 writer App으로 인증한다(P2 variables github_app_*). ID 두 개는 lab.env에 있다.
  # 예: SETTINGS_WRITER_APP_ID=1234567, SETTINGS_WRITER_INSTALLATION_ID=87654321,
  #     SETTINGS_WRITER_PEM_FILE=/home/vscode/commerce-admin/work/github-settings-writer.pem
  # private key는 파일 경로가 아니라 내용을 넘긴다. 이 script 프로세스의 환경 변수에만 있고 화면·기록에는 나오지 않는다.
  : "${SETTINGS_WRITER_APP_ID:?lab.env에 SETTINGS_WRITER_APP_ID가 없습니다}"
  : "${SETTINGS_WRITER_INSTALLATION_ID:?lab.env에 SETTINGS_WRITER_INSTALLATION_ID가 없습니다}"
  : "${SETTINGS_WRITER_PEM_FILE:?lab.env에 SETTINGS_WRITER_PEM_FILE이 없습니다}"
  [ -f "$SETTINGS_WRITER_PEM_FILE" ] || fail "writer App key 파일이 없습니다: $SETTINGS_WRITER_PEM_FILE (App 화면 → Generate a private key)"
  export TF_VAR_github_app_id="$SETTINGS_WRITER_APP_ID"
  export TF_VAR_github_app_installation_id="$SETTINGS_WRITER_INSTALLATION_ID"
  TF_VAR_github_app_private_key=$(cat "$SETTINGS_WRITER_PEM_FILE")
  export TF_VAR_github_app_private_key
  # 세 값은 ephemeral 변수라 저장한 plan에 들어가지 않는다. 같은 프로세스의 apply가 환경 변수로 다시 받는다.
fi

# backend "s3"가 있는 stack(02-04 이관 뒤, github stack)은 State Bucket을 init 인자로 받는다.
init_args=(-input=false)
if grep -q 'backend "s3"' "$stack_dir"/*.tf; then
  state_account_id=$(jq -r --arg account "$state_account" '.[$account]' <<<"$TF_VAR_account_ids")
  # 예: cloud-platform-prod-tfstate-222222222222, alias/cloud-platform-prod-tfstate
  init_args+=("-backend-config=bucket=cloud-platform-$state_account-tfstate-$state_account_id")
  init_args+=("-backend-config=kms_key_id=alias/cloud-platform-$state_account-tfstate")
fi

terraform -chdir="$stack_dir" init "${init_args[@]}"
terraform -chdir="$stack_dir" plan -input=false -out=tfplan

read -r -p "위 plan을 apply할까요? yes를 입력합니다: " answer
if [ "$answer" != yes ]; then
  rm -f "$stack_dir/tfplan"
  fail "apply하지 않았습니다"
fi

# 기록: 어떤 commit의 어떤 plan을 누가 적용했는지. Account ID는 public PR에 붙이므로 가린다.
mkdir -p "$records_dir"
{
  echo "stack: ${stack_dir#"$root_dir"/}"
  echo "commit: $(git -C "$root_dir" rev-parse HEAD)"
  echo "utc: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "operator: $(aws sts get-caller-identity --query Arn --output text)"
  terraform -chdir="$stack_dir" show -no-color tfplan
} | sed -E 's/[0-9]{12}/<account>/g' >"$record_file"

terraform -chdir="$stack_dir" apply -input=false tfplan
# 저장한 plan에는 변수 값이 들어 있으므로 apply 뒤 지운다.
rm -f "$stack_dir/tfplan"
note "기록: $record_file"
