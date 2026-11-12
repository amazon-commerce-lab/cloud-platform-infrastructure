#!/usr/bin/env bash
# 개인 IAM DB 접속용 port forwarding을 연다(15-10). 이 터미널은 열어 두고, 다른 터미널에서 make db-psql을 실행한다.
# 사용: scripts/ops/db-connect.sh <dev|prod>
#   문서: commerce-<env>-rds-port-forward(목적지 RDS 5432 고정) → 127.0.0.1:15432(dev)·15433(prod)
#   profile: Permission Set DatabaseReader. dev는 dev-db-reader(개발용 container, 상시 배정),
#            prod는 prod-db-jit(관리용 container, make jit ACCOUNT=prod PERMISSION_SET=DatabaseReader 승인 뒤 1시간)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -ne 1 ]; then
  echo "사용: $0 <dev|prod>" >&2
  exit 2
fi
env_name="$1"
require_env_name "$env_name"
profile=$(db_profile "$env_name")
local_port=$(db_local_port "$env_name")

# 예: i-0123456789abcdef0
relay_id=$(ssm_value "$profile" "/commerce/$env_name/eks/relay-instance-id")

note "commerce-$env_name-rds-port-forward → 127.0.0.1:$local_port (profile $profile)"
exec aws ssm start-session --profile "$profile" \
  --target "$relay_id" \
  --document-name "commerce-$env_name-rds-port-forward" \
  --parameters "localPortNumber=$local_port"
