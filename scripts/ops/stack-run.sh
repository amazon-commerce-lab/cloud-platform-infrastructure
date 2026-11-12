#!/usr/bin/env bash
# 등록된 Terraform stack 하나를 terraform.yml 수동 실행(workflow_dispatch)으로 plan·apply·destroy하고 끝까지 지켜본다.
# 사용: scripts/ops/stack-run.sh <stack> <plan|apply|destroy>
#   stack: terraform/environments/ 아래 경로. 예: dev/compute/eks, prod/edge, management/identity
#          GitHub 설정 stack은 github/settings
#   예: scripts/ops/stack-run.sh dev/compute/eks destroy   (pause 가이드)
#       scripts/ops/stack-run.sh dev/compute/eks apply     (resume 가이드)
#       scripts/ops/stack-run.sh prod/edge plan            (main 기준 plan만, 결과는 run Summary)
# Dev layer는 바로 적용하고, 나머지 stack은 저장 plan → 승인자 승인 → 적용 순서다(select-terraform-stacks.py dispatch).
# 승인이 필요한 run이면 아래 run 링크를 승인자에게 보낸다. 승인 전에는 gh run watch가 대기 상태로 남는다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -ne 2 ]; then
  echo "사용: $0 <stack 예: dev/compute/eks> <plan|apply|destroy>" >&2
  exit 2
fi
stack="$1"
action="$2"
case "$action" in
  plan | apply | destroy) ;;
  *) fail "ACTION은 plan, apply, destroy 중 하나입니다. 받은 값: '$action'" ;;
esac
cd "$(infra_root)"

if [ "$stack" = github/settings ]; then
  working_directory="terraform/github/settings"
else
  working_directory="terraform/environments/$stack"
fi
# backend.tf가 있는 폴더만 stack이다. 오타면 dispatch 전에 멈춘다.
if [ ! -f "$working_directory/backend.tf" ]; then
  fail "$working_directory 에 backend.tf가 없습니다. STACK=<env>/<path> 형식인지 봅니다. 예: STACK=dev/compute/eks"
fi

# gh workflow run은 만든 run의 URL을 출력한다(jit-request.sh와 같은 방식).
# 예: https://github.com/zoopang-1234/cloud-platform-infrastructure/actions/runs/123
dispatch_output=$(gh workflow run terraform.yml --ref main \
  -f working_directory="$working_directory" \
  -f action="$action")
echo "$dispatch_output"
if ! run_url=$(grep -Eo 'https://[^ ]+/actions/runs/[0-9]+' <<<"$dispatch_output"); then
  fail "run URL을 찾지 못했습니다. gh 2.80 이상인지 확인합니다."
fi

note "$action $working_directory: $run_url"
note "Dev layer가 아니면 승인자에게 이 링크를 보냅니다(Review deployments)."
gh run watch "${run_url##*/}" --exit-status
if [ "$action" = plan ]; then
  note "plan 요약은 run 화면 Summary에 있습니다: $run_url"
fi
