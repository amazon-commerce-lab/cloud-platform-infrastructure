# shellcheck shell=bash
# scripts/ops/*.sh가 같이 쓰는 함수. 직접 실행하지 않고 각 script가 source한다.
# 환경 이름·접근 방식·profile·context·port 규칙을 한곳에 둔다.

# 오류를 stderr로 내고 끝낸다. 예: fail "ENV는 dev 또는 prod입니다"
fail() {
  echo "오류: $*" >&2
  exit 1
}

# 진행 상황을 stderr로 낸다. stdout은 다음 명령에 넘길 값만 쓴다.
note() {
  echo "==> $*" >&2
}

require_env_name() {
  case "$1" in
    dev | prod) ;;
    *) fail "ENV는 dev 또는 prod입니다. 받은 값: '$1'" ;;
  esac
}

# 환경마다 기본 접근 방식. 개발용 container의 Dev는 operator, 관리용 container의 Prod는 viewer.
default_access() {
  case "$1" in
    dev) echo operator ;;
    prod) echo viewer ;;
  esac
}

# ACCESS → AWS profile. 예: admin + dev → dev-admin-jit
profile_for_access() {
  local env_name="$1"
  local access="$2"
  case "$env_name:$access" in
    dev:operator) echo dev-operator ;;
    prod:viewer) echo prod-viewer ;;
    prod:readonly) echo prod-developer ;;
    dev:admin | prod:admin) echo "$env_name-admin-jit" ;;
    *) fail "ENV=${env_name}에서는 ACCESS=${access}를 쓰지 않습니다(dev: operator·admin, prod: viewer·admin·readonly)" ;;
  esac
}

# ACCESS → kubectl context 이름. 예: admin + prod → commerce-prod-eks-admin
context_for_access() {
  local env_name="$1"
  local access="$2"
  case "$access" in
    operator | viewer) echo "commerce-$env_name-eks" ;;
    admin) echo "commerce-$env_name-eks-admin" ;;
    readonly) echo "commerce-$env_name-eks-readonly" ;;
  esac
}

# 로컬 port. 두 환경 터널을 같이 열어도 겹치지 않게 나눈다.
#   dev 18080, prod 18081, Prod 개발자 squid 18082
tunnel_port() {
  local env_name="$1"
  local access="$2"
  if [ "$access" = readonly ]; then
    echo 18082
  elif [ "$env_name" = dev ]; then
    echo 18080
  else
    echo 18081
  fi
}

# Terraform이 쓴 SSM Parameter 한 개를 읽는다.
# 예: ssm_value dev-operator /commerce/dev/eks/relay-instance-id → i-0123456789abcdef0
ssm_value() {
  local profile="$1"
  local name="$2"
  aws ssm get-parameter --profile "$profile" --name "$name" --query Parameter.Value --output text
}

# infra repository 최상위(scripts/ops의 두 단계 위). Makefile 밖에서 script를 불러도 같은 위치에서 돈다.
# 예: /home/vscode/commerce-admin/cloud-platform-infrastructure
infra_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

# 로컬 bootstrap(02장)에서 Account별 profile. management·github stack은 Management bootstrap profile을 쓴다.
# 예: prod → prod-bootstrap, management → mgmt-bootstrap-admin
bootstrap_profile() {
  case "$1" in
    management | github) echo mgmt-bootstrap-admin ;;
    network | dev | prod | security | log-archive | backup) echo "$1-bootstrap" ;;
    *) fail "ACCOUNT는 management, network, dev, prod, security, log-archive, backup, github 중 하나입니다. 받은 값: '$1'" ;;
  esac
}

# 로컬 Terraform 실행에 CI와 같은 입력을 넣는다(CI는 vars.ACCOUNT_IDS·github.repository_owner로 넣는다).
#   TF_VAR_account_ids  = Organization Account 목록에서 만든 map. 예: {"dev":"111111111111",...}
#   TF_VAR_github_owner = 이 repository의 GitHub 조직. 예: zoopang-1234
export_bootstrap_inputs() {
  local management_account_id
  management_account_id=$(aws organizations describe-organization --profile mgmt-bootstrap-admin \
    --query Organization.MasterAccountId --output text)
  TF_VAR_account_ids=$(aws organizations list-accounts --profile mgmt-bootstrap-admin --output json |
    jq -c --arg management "$management_account_id" -f "$(dirname "${BASH_SOURCE[0]}")/account-ids.jq")
  TF_VAR_github_owner=$(gh repo view --json owner --jq .owner.login)
  export TF_VAR_account_ids TF_VAR_github_owner
}

# 개인 DB 접속 터널의 로컬 port. 예: dev 15432, prod 15433
# 개인 DB 접속 profile. Dev는 개발용 container의 상시 배정, Prod는 관리용 container의 JIT 배정(15-10).
# 예: dev → dev-db-reader, prod → prod-db-jit
db_profile() {
  case "$1" in
    dev) echo dev-db-reader ;;
    prod) echo prod-db-jit ;;
  esac
}

db_local_port() {
  case "$1" in
    dev) echo 15432 ;;
    prod) echo 15433 ;;
  esac
}
