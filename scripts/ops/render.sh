#!/usr/bin/env bash
# 등록된 Argo CD Application 하나를 cluster 없이 렌더링해 stdout으로 낸다. 값 파일·chart 버전은 Application에 적힌 그대로 쓴다.
# 사용: scripts/ops/render.sh <app> <dev|prod>
#   예: scripts/ops/render.sh holmes dev | less
#       scripts/ops/render.sh holmes dev | yq 'select(.kind == "Deployment") | .metadata.name'
#   Application 찾기: gitops/clusters/<env>를 렌더링해 이름이 <app>인 Application을 고른다(cluster에 등록되는 것과 같은 목록).
#   source 종류: Git path → kubectl kustomize(CI의 gitops-render-all과 같음),
#                Helm chart → helm template --repo(원격 chart를 받는다. CI는 chart를 렌더링하지 않으므로 결과는 여기서 본다)
# Account ID 자리(000000000000)는 그대로 나온다. 실제 값은 cluster에서 root ApplicationSet이 넣는다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -ne 2 ]; then
  echo "사용: $0 <app> <dev|prod>" >&2
  exit 2
fi
app_name="$1"
env_name="$2"
require_env_name "$env_name"
cd "$(infra_root)"

application=$(kubectl kustomize "gitops/clusters/$env_name" |
  APP_NAME="$app_name" yq 'select(.kind == "Application" and .metadata.name == strenv(APP_NAME))')
[ -n "$application" ] || fail "gitops/clusters/${env_name}에 Application '$app_name'이 없습니다"

namespace=$(yq '.spec.destination.namespace' <<<"$application")
# source가 하나면 .spec.source, 여럿이면 .spec.sources. 하나의 목록으로 다룬다.
source_count=$(yq '(.spec.sources // [.spec.source]) | length' <<<"$application")

for ((source_index = 0; source_index < source_count; source_index++)); do
  source_spec=$(yq "(.spec.sources // [.spec.source])[$source_index]" <<<"$application")
  chart=$(yq '.chart // ""' <<<"$source_spec")
  source_path=$(yq '.path // ""' <<<"$source_spec")

  if [ -n "$chart" ]; then
    repo_url=$(yq '.repoURL' <<<"$source_spec")
    chart_version=$(yq '.targetRevision' <<<"$source_spec")
    release_name=$(APP_NAME="$app_name" yq '.helm.releaseName // strenv(APP_NAME)' <<<"$source_spec")
    note "helm template $chart $chart_version ($repo_url)"

    # valueFiles의 $values/는 이 repository 최상위다. 예: $values/gitops/platform/holmes/values-dev.yaml
    value_args=()
    while read -r value_file; do
      [ -n "$value_file" ] || continue
      value_args+=(-f "${value_file#\$values/}")
    done < <(yq '.helm.valueFiles[]?' <<<"$source_spec")

    # Argo CD는 skipCrds가 아니면 CRD도 적용한다.
    crd_args=(--include-crds)
    if [ "$(yq '.helm.skipCrds // false' <<<"$source_spec")" = true ]; then
      crd_args=()
    fi

    # valuesObject는 값 파일보다 우선하므로 마지막 -f로 넘긴다(stdin).
    yq '.helm.valuesObject // {}' <<<"$source_spec" |
      helm template "$release_name" "$chart" --repo "$repo_url" --version "$chart_version" \
        --namespace "$namespace" "${crd_args[@]}" "${value_args[@]}" -f -
  elif [ -n "$source_path" ]; then
    note "kubectl kustomize $source_path"
    kubectl kustomize "$source_path"
  fi
  # ref만 있는 source(예: ref: values)는 값 파일 위치를 알려 줄 뿐 렌더링할 내용이 없다.
done
