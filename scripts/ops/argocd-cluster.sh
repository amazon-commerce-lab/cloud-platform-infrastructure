#!/usr/bin/env bash
# Argo CD in-cluster Secret을 SSM 값으로 만든다. root ApplicationSet이 이 Secret의 label·annotation을 읽는다.
# 사용: scripts/ops/argocd-cluster.sh <dev|prod>
#   값: SSM /commerce/<env>/argocd/cluster/{account-id,region,data-cidr,endpoint-cidr,kubernetes-api-cidr}
#   권한: JIT <env>-admin-jit, context commerce-<env>-eks-admin. 터널(make eks-tunnel ACCESS=admin)이 열려 있어야 한다.
# 같은 값이면 kubectl diff가 비어 있고 apply도 unchanged다. VPC를 다시 만들어 값이 바뀌었을 때 다시 실행한다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -ne 1 ]; then
  echo "사용: $0 <dev|prod>" >&2
  exit 2
fi
env_name="$1"
require_env_name "$env_name"
profile=$(profile_for_access "$env_name" admin)
context_name=$(context_for_access "$env_name" admin)
parameter_prefix="/commerce/$env_name/argocd/cluster"

# 예: 111111111111, ap-northeast-2, 172.20.0.0/17, 172.20.128.0/18, 172.20.0.0/17
account_id=$(ssm_value "$profile" "$parameter_prefix/account-id")
region=$(ssm_value "$profile" "$parameter_prefix/region")
data_cidr=$(ssm_value "$profile" "$parameter_prefix/data-cidr")
endpoint_cidr=$(ssm_value "$profile" "$parameter_prefix/endpoint-cidr")
kubernetes_api_cidr=$(ssm_value "$profile" "$parameter_prefix/kubernetes-api-cidr")

# 하나라도 비면 root ApplicationSet 렌더링이 missingkey로 멈춘다. Secret을 만들기 전에 여기서 멈춘다.
for annotation_value in "$account_id" "$region" "$data_cidr" "$endpoint_cidr" "$kubernetes_api_cidr"; do
  if [ -z "$annotation_value" ] || [ "$annotation_value" = None ]; then
    fail "$parameter_prefix/* 중 빈 값이 있습니다. compute/eks stack apply가 끝났는지 확인합니다."
  fi
done

# Argo CD가 in-cluster로 인식하는 cluster Secret. annotation 키 5개는 고정이다(root ApplicationSet이 읽음).
cluster_secret=$(
  cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: in-cluster
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    commerce.example/env: $env_name
  annotations:
    commerce.example/account-id: "$account_id"
    commerce.example/region: $region
    commerce.example/data-cidr: $data_cidr
    commerce.example/endpoint-cidr: $endpoint_cidr
    commerce.example/kubernetes-api-cidr: $kubernetes_api_cidr
stringData:
  name: in-cluster
  server: https://kubernetes.default.svc
EOF
)

# kubectl diff는 차이가 있으면 1, 오류면 2 이상을 돌려준다. 1은 정상(바뀔 내용이 있음)으로 보고 계속한다.
diff_status=0
kubectl --context "$context_name" diff -f - <<<"$cluster_secret" || diff_status=$?
if [ "$diff_status" -gt 1 ]; then
  fail "kubectl diff 실패(exit $diff_status)"
fi

kubectl --context "$context_name" apply -f - <<<"$cluster_secret"
