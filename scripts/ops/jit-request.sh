#!/usr/bin/env bash
# JIT 관리자 배정을 요청하고, 승인·배정이 끝날 때까지 run을 지켜본 뒤 SSO에 다시 로그인한다.
# 사용: scripts/ops/jit-request.sh <account> <permission-set> <hours> <ticket> <reason>
#   예: scripts/ops/jit-request.sh dev PlatformAdmin 2 CHG-1 "Argo CD 첫 설치(08-07)"
# 승인은 승인자가 browser에서 합니다(run 화면 → Review deployments → jit-admin-approval).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -ne 5 ]; then
  echo "사용: $0 <account> <PlatformAdmin|InfrastructureProvisioner|OrganizationAdministrator|DatabaseReader> <1-4> <ticket> <reason>" >&2
  exit 2
fi
account="$1"
permission_set="$2"
hours="$3"
ticket="$4"
reason="$5"
cd "$(infra_root)"

# gh workflow run은 만든 run의 URL을 출력한다. 예: https://github.com/zoopang-1234/cloud-platform-infrastructure/actions/runs/123
dispatch_output=$(gh workflow run jit-admin-grant.yml --ref main \
  -f account="$account" \
  -f permission_set="$permission_set" \
  -f hours="$hours" \
  -f ticket="$ticket" \
  -f reason="$reason")
echo "$dispatch_output"
if ! run_url=$(grep -Eo 'https://[^ ]+/actions/runs/[0-9]+' <<<"$dispatch_output"); then
  fail "run URL을 찾지 못했습니다. gh 2.80 이상인지 확인합니다."
fi

note "승인자에게 이 링크를 보냅니다: $run_url"
gh run watch "${run_url##*/}" --exit-status

# 배정이 생긴 뒤 다시 로그인해야 새 Permission Set이 SSO cache에 들어간다.
aws sso login --sso-session commerce-admin

# 받은 Permission Set에 맞는 profile 이름. 예: dev + PlatformAdmin → dev-admin-jit
case "$permission_set" in
  PlatformAdmin) jit_profile="$account-admin-jit" ;;
  InfrastructureProvisioner) jit_profile="$account-provisioner-jit" ;;
  OrganizationAdministrator) jit_profile=mgmt-admin-jit ;;
  DatabaseReader) jit_profile="$account-db-jit" ;; # 예: prod-db-jit. make db-connect·db-psql ENV=prod가 이 profile을 쓴다(15-10)
  *) fail "알 수 없는 Permission Set: $permission_set" ;;
esac
if [ "$permission_set" = DatabaseReader ]; then
  note "배정 완료. DB 조회는 터미널 2의 make db-connect ENV=$account와 make db-psql ENV=$account로 합니다(profile ${jit_profile})."
else
  note "배정 완료. 관리 명령에 --profile ${jit_profile}을 붙입니다."
  note "kubectl은 처음이면 make kubeconfig ENV=$account ACCESS=admin, 그 뒤 --context commerce-$account-eks-admin을 씁니다."
fi
