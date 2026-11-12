#!/usr/bin/env bash
# kubectl context를 만들고 cluster 주소를 SSM 터널(127.0.0.1)로 돌린다. context마다 처음 한 번만 실행한다.
# kubeconfig의 exec plugin에는 AWS_PROFILE만 들어가므로 JIT를 새로 받아도 다시 만들 필요가 없다(make jit가 SSO 재로그인까지 한다).
# 사용: scripts/ops/kubeconfig.sh <dev|prod> [operator|viewer|admin|readonly]
#   operator → commerce-dev-eks (dev-operator)        viewer   → commerce-prod-eks (prod-viewer)
#   admin    → commerce-<env>-eks-admin (<env>-admin-jit) readonly → commerce-prod-eks-readonly (prod-developer, squid)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -lt 1 ]; then
  echo "사용: $0 <dev|prod> [operator|viewer|admin|readonly]" >&2
  exit 2
fi
env_name="$1"
require_env_name "$env_name"
access="${2:-$(default_access "$env_name")}"
profile=$(profile_for_access "$env_name" "$access")
context_name=$(context_for_access "$env_name" "$access")
local_port=$(tunnel_port "$env_name" "$access")

# 예: commerce-dev-eks, ABCD1234.gr7.ap-northeast-2.eks.amazonaws.com
cluster_name=$(ssm_value "$profile" "/commerce/$env_name/eks/cluster-name")
endpoint_host=$(ssm_value "$profile" "/commerce/$env_name/eks/endpoint-host")

# admin context를 만들어도 지금 쓰던 기본 context는 그대로 둔다. 관리 작업은 명령마다 --context로 고른다.
# current-context가 아직 없으면(처음 실행) 빈 값이 나오고 오류는 아니다.
previous_context=$(kubectl config view -o jsonpath='{.current-context}')

# update-kubeconfig는 user exec에 AWS_PROFILE=<profile>을 적는다. context마다 profile이 묶인다.
# user 이름도 context 이름으로 둔다. 기본값(cluster ARN)이면 같은 cluster의 viewer·admin context가 user 하나를 덮어쓴다.
aws eks update-kubeconfig --profile "$profile" --name "$cluster_name" --alias "$context_name" --user-alias "$context_name"
cluster_entry=$(kubectl config view -o jsonpath="{.contexts[?(@.name==\"$context_name\")].context.cluster}")

if [ "$access" = readonly ]; then
  # Prod 개발자는 squid를 proxy로 쓴다. server는 원래 endpoint 그대로라 인증서 검증이 바뀌지 않는다.
  kubectl config set-cluster "$cluster_entry" --proxy-url="http://127.0.0.1:$local_port"
else
  # 터널은 TLS를 풀지 않고 넘긴다. 주소만 127.0.0.1로 바꾸고 인증서 이름은 원래 endpoint host로 검증한다.
  kubectl config set-cluster "$cluster_entry" \
    --server="https://127.0.0.1:$local_port" \
    --tls-server-name="$endpoint_host"
fi

if [ "$access" = admin ] && [ -n "$previous_context" ]; then
  kubectl config use-context "$previous_context"
fi

note "context $context_name 준비 완료. 터널: make eks-tunnel ENV=$env_name ACCESS=$access"
