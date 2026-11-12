#!/usr/bin/env bash
# 자기 이름의 DB Role(op_<userName>)로 IAM 인증 token을 받아 psql을 연다(15-10). make db-connect 터널이 열려 있어야 한다.
# Prod는 관리용 container에서 DatabaseReader JIT(profile prod-db-jit)를 받은 동안만 된다. 개인정보 table은 masked view로만 읽는다.
# 사용: scripts/ops/db-psql.sh <dev|prod> [psql 인자...]
#   예: scripts/ops/db-psql.sh dev -c 'SELECT session_user, current_user;'
#   token은 15분 유효하고 psql 한 번에만 넘긴다. 파일·환경 변수로 남기지 않는다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -lt 1 ]; then
  echo "사용: $0 <dev|prod> [psql 인자...]" >&2
  exit 2
fi
env_name="$1"
shift
require_env_name "$env_name"
profile=$(db_profile "$env_name")
local_port=$(db_local_port "$env_name")
ca_bundle="$(infra_root)/gitops/components/rds-ca/rds-ca.pem"

# DB 사용자는 SSO 세션 이름(Identity Center userName)으로 정해진다. 예: ...:assumed-role/AWSReservedSSO_DatabaseReader_.../dohyun_platform → op_dohyun_platform
caller_arn=$(aws sts get-caller-identity --profile "$profile" --query Arn --output text)
db_user="op_${caller_arn##*/}"

# 인증서 이름 검증은 실제 RDS host로, 연결은 터널(127.0.0.1)로 한다.
# 예: commerce-dev-postgres.abcdefghijkl.ap-northeast-2.rds.amazonaws.com
db_instance_id=$(ssm_value "$profile" "/commerce/$env_name/data/postgres-instance-id")
db_host=$(aws rds describe-db-instances --profile "$profile" --db-instance-identifier "$db_instance_id" \
  --query 'DBInstances[0].Endpoint.Address' --output text)

PGPASSWORD=$(aws rds generate-db-auth-token --profile "$profile" --hostname "$db_host" --port 5432 --username "$db_user") \
  psql "host=$db_host hostaddr=127.0.0.1 port=$local_port dbname=commerce user=$db_user sslmode=verify-full sslrootcert=$ca_bundle" \
  -X "$@"
