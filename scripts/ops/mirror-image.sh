#!/usr/bin/env bash
# 외부 image를 digest 그대로 그 환경의 ECR mirror/로 복사한다(18-13 Dev, 18-19 Prod). mirror/ 쓰기는 JIT 관리자만 할 수 있다.
# 사용: scripts/ops/mirror-image.sh <source@sha256:digest> <dev|prod> <tag>
#   예: scripts/ops/mirror-image.sh \
#         us-central1-docker.pkg.dev/genuine-flight-317411/mcp/aws-api-mcp-server@sha256:bc125264...e7350e dev 2.1.0
#       → 111111111111.dkr.ecr.ap-northeast-2.amazonaws.com/mirror/aws-api-mcp-server:2.1.0
# 권한: <env>-admin-jit. 복사 사유와 원본 digest는 변경 기록에 남긴다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -ne 3 ]; then
  echo "사용: $0 <source@sha256:digest> <dev|prod> <tag>" >&2
  exit 2
fi
source_image="$1"
env_name="$2"
tag="$3"
require_env_name "$env_name"
case "$source_image" in
  *@sha256:*) ;;
  *) fail "원본은 digest로 지정합니다. 예: registry/path/name@sha256:<64자리>" ;;
esac
profile=$(profile_for_access "$env_name" admin)

source_digest="${source_image##*@}"
image_name=$(basename "${source_image%@*}")
account_id=$(ssm_value "$profile" "/commerce/$env_name/argocd/cluster/account-id")
registry="$account_id.dkr.ecr.ap-northeast-2.amazonaws.com"
destination="$registry/mirror/$image_name:$tag"

aws ecr get-login-password --profile "$profile" | crane auth login "$registry" -u AWS --password-stdin
crane copy "$source_image" "$destination"

# 복사본이 원본과 같은 digest인지 본다. 다르면 다른 image가 들어간 것이다.
copied_digest=$(crane digest "$destination")
if [ "$copied_digest" != "$source_digest" ]; then
  fail "digest가 다릅니다. 원본 $source_digest, 복사본 $copied_digest"
fi
note "$destination@$copied_digest"
