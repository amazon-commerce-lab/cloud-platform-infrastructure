#!/usr/bin/env bash
# EKS private API로 가는 SSM 터널을 연다. 이 터미널은 열어 둔다(Ctrl+C로 닫음).
# 사용: scripts/ops/eks-tunnel.sh <dev|prod> [operator|viewer|admin|readonly]
#   엔지니어: 전용 문서 commerce-<env>-eks-api-tunnel → 127.0.0.1:18080(dev)·18081(prod)
#   Prod 개발자(readonly): 전용 문서 commerce-prod-squid-port-forward → 127.0.0.1:18082(squid)
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
local_port=$(tunnel_port "$env_name" "$access")

if [ "$access" = readonly ]; then
  document_name="commerce-$env_name-squid-port-forward"
else
  document_name="commerce-$env_name-eks-api-tunnel"
fi

# relay ID는 compute/eks stack이 SSM에 쓴다. 예: i-0123456789abcdef0
relay_id=$(ssm_value "$profile" "/commerce/$env_name/eks/relay-instance-id")

note "$document_name → 127.0.0.1:$local_port (profile $profile, relay $relay_id)"
exec aws ssm start-session --profile "$profile" \
  --target "$relay_id" \
  --document-name "$document_name" \
  --parameters "localPortNumber=$local_port"
