#!/usr/bin/env bash
# 새 cluster에 Argo CD를 처음 올린다(08-07 Dev, 17-18 Prod). 그 뒤 Argo CD 자신은 GitOps(argocd Application)가 관리한다.
# 사용: scripts/ops/argocd-bootstrap.sh <dev|prod>
#   1) helm install argocd: main의 values.yaml + values-<env>.yaml (이미 설치돼 있으면 건너뜀)
#   2) kubectl apply -k AppProject (dev: gitops/projects, prod: gitops/projects/prod — sync window 포함)
#   3) in-cluster Secret (argocd-cluster.sh)
#   4) kubectl apply -f gitops/bootstrap/root.yaml (root ApplicationSet)
# 권한: JIT <env>-admin-jit, context commerce-<env>-eks-admin. 터널이 열려 있어야 한다. 다시 실행해도 결과가 같다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# gitops/releases/<env>/platform/argocd.yaml의 chart targetRevision과 같아야 한다. 다르면 08-08 첫 sync가 upgrade를 한다.
argocd_chart_version="10.9.0"

if [ "$#" -ne 1 ]; then
  echo "사용: $0 <dev|prod>" >&2
  exit 2
fi
env_name="$1"
require_env_name "$env_name"
context_name=$(context_for_access "$env_name" admin)
cd "$(infra_root)"

if [ "$env_name" = prod ]; then
  projects_dir=gitops/projects/prod
else
  projects_dir=gitops/projects
fi

# 08-08 뒤에는 argocd Application이 같은 release를 관리한다. 여기서 다시 helm upgrade하지 않는다.
# release가 없으면 빈 값이 나온다. cluster에 닿지 않으면 helm 오류로 그대로 멈춘다.
if [ -n "$(helm --kube-context "$context_name" -n argocd list --short --filter '^argocd$')" ]; then
  note "helm release argocd가 이미 있어 설치를 건너뜁니다"
else
  note "helm install argocd $argocd_chart_version"
  helm install argocd argo-cd --kube-context "$context_name" \
    --repo https://argoproj.github.io/argo-helm --version "$argocd_chart_version" \
    --namespace argocd --create-namespace \
    -f gitops/platform/argocd/values.yaml \
    -f "gitops/platform/argocd/values-$env_name.yaml" \
    --wait --timeout 15m
fi

# root가 bootstrap project를 쓰므로 AppProject를 먼저 만든다.
note "AppProject ($projects_dir)"
kubectl --context "$context_name" apply -k "$projects_dir"

note "in-cluster Secret"
"$(dirname "$0")/argocd-cluster.sh" "$env_name"

note "root ApplicationSet"
kubectl --context "$context_name" apply -f gitops/bootstrap/root.yaml
