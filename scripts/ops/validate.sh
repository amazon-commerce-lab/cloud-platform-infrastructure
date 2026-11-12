#!/usr/bin/env bash
# Terraform 로컬 검사: 저장소 전체 TFLint를 실행한 뒤, 지정하거나 바뀐 stack마다 fmt -check → init -backend=false → validate를 실행한다.
# TFLint는 PR의 validate-source check와 같은 설정(.tflint.hcl)·같은 범위(저장소 전체)다. 저장소 전체 fmt와 Account ID 검사, module test는 PR check에서 본다.
# 사용: scripts/ops/validate.sh [stack ...]
#   stack 예: dev/compute/eks (terraform/environments 아래), github/settings, modules/eks (terraform 아래)
#   stack을 주지 않으면 origin/main에서 갈라진 뒤 바뀐 stack을 모두 검사한다.
# .terraform/과 .terraform.lock.hcl은 지우지 않는다. lock 파일은 처음 생기면 commit한다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(infra_root)"

# GitOps만 바뀌어도 CI와 같은 범위로 Terraform 선언을 검사한다.
# 예: 선언만 하고 쓰지 않는 variable·local·data(terraform_unused_declarations)가 저장소 어디에 있어도 여기서 실패한다.
note "저장소 전체 TFLint(.tflint.hcl)"
tflint --init --config "$PWD/.tflint.hcl"
tflint --recursive --config "$PWD/.tflint.hcl"

# stack 인자를 실제 폴더로 바꾼다. 예: dev/compute/eks → terraform/environments/dev/compute/eks
resolve_stack() {
  local stack="$1"
  if [ -d "terraform/environments/$stack" ]; then
    echo "terraform/environments/$stack"
  elif [ -d "terraform/$stack" ]; then
    echo "terraform/$stack"
  elif [ -d "$stack" ]; then
    echo "${stack%/}"
  else
    fail "stack 폴더가 없습니다: $stack"
  fi
}

# 바뀐 파일(commit 전 수정·새 파일 포함)이 들어 있는 Terraform 폴더 목록
changed_stacks() {
  {
    git diff --name-only --merge-base origin/main -- terraform
    git ls-files --others --exclude-standard -- terraform
  } | while read -r changed_file; do
    stack_dir=$(dirname "$changed_file")
    if compgen -G "$stack_dir/*.tf" >/dev/null; then
      echo "$stack_dir"
    fi
  done | sort -u
}

if [ "$#" -gt 0 ]; then
  stack_dirs=()
  for stack in "$@"; do
    stack_dirs+=("$(resolve_stack "$stack")")
  done
else
  mapfile -t stack_dirs < <(changed_stacks)
  if [ "${#stack_dirs[@]}" -eq 0 ]; then
    note "origin/main 이후 바뀐 Terraform 폴더가 없습니다. 특정 stack은 STACK=dev/compute/eks처럼 지정합니다."
    exit 0
  fi
fi

for stack_dir in "${stack_dirs[@]}"; do
  note "$stack_dir"
  terraform -chdir="$stack_dir" fmt -check -diff
  terraform -chdir="$stack_dir" init -backend=false -input=false
  terraform -chdir="$stack_dir" validate
done
