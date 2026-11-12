#!/usr/bin/env bash
# PR의 gitops-render-all check와 같은 검사를 로컬에서 한다. workflow(gitops-required.yml)도 이 script를 부른다.
# 사용: scripts/ops/gitops-check.sh <dev|prod>
#   1) gitops 아래 모든 kustomization 렌더링
#   2) gitops/clusters/<env> 렌더링 → 필수 Application 검사(ci.gitops.required_apps)
#   3) Holmes Skill 원본과 values 비교(holmes-skills-check.sh)
#   4) ci/gitops/render-targets.yaml의 <env> 대상 렌더링 → image digest·namespace 범위 검사(ci.gitops.validate_contract)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -ne 1 ]; then
  echo "사용: $0 <dev|prod>" >&2
  exit 2
fi
env_name="$1"
require_env_name "$env_name"
cd "$(infra_root)"

# Prod 등록 목록은 17장에서 생긴다. 그 전에는 Prod 검사를 건너뛴다.
if [ ! -d "gitops/clusters/$env_name" ]; then
  note "gitops/clusters/${env_name}이 아직 없어 $env_name 검사를 건너뜁니다"
  exit 0
fi

note "모든 kustomization 렌더링"
render_failures=0
while read -r kustomize_dir; do
  if ! kubectl kustomize "$kustomize_dir" >/dev/null; then
    echo "렌더링 실패: $kustomize_dir" >&2
    render_failures=$((render_failures + 1))
  fi
done < <(find gitops -name kustomization.yaml -exec dirname {} \; | sort)
if [ "$render_failures" -gt 0 ]; then
  fail "렌더링 실패 ${render_failures}곳"
fi

note "gitops/clusters/$env_name 필수 Application"
kubectl kustomize "gitops/clusters/$env_name" |
  python3 -m ci.gitops.required_apps --env "$env_name" --rendered /dev/stdin --repo-root .

# make init-template(01-01) 전이면 HTTPRoute hostnames가 "dev.<상위 도메인 placeholder>"라서 schema의 hostname 형식(RFC 1123)에 맞지 않고
# validate_contract가 OPENAPI_SCHEMA로 멈춘다. 원인이 코드가 아니라 초기화 누락이므로 그 말을 먼저 한다.
# placeholder 글자를 그대로 쓰면 init-template이 이 줄도 바꾸므로 "dev.<" 형태로 찾는다.
if grep -rqF 'dev.<' gitops/apps; then
  fail "gitops/apps의 hostname에 상위 도메인 placeholder가 남아 있습니다. make init-template을 먼저 실행합니다(01-01)"
fi

# Holmes Skill은 SKILL.md 원본과 values 두 곳에 같은 글이 있어야 한다(18-12).
"$(dirname "$0")/holmes-skills-check.sh"

# render-targets.yaml의 id는 <app>-<env> 형식이다. 예: api-dev → gitops/apps/commerce-api/overlays/dev
while read -r target_id target_path; do
  # 앱 overlay는 14장, Prod overlay는 17장에서 생긴다. 아직 없는 target은 건너뛴다.
  if [ ! -d "$target_path" ]; then
    note "$target_id: ${target_path}가 아직 없어 건너뜁니다"
    continue
  fi
  note "$target_id ($target_path)"
  kubectl kustomize "$target_path" |
    python3 -m ci.gitops.validate_contract --target "$target_id" --rendered /dev/stdin
done < <(yq ".targets[] | select(.id | test(\"-$env_name\$\")) | .id + \" \" + .path" ci/gitops/render-targets.yaml)
