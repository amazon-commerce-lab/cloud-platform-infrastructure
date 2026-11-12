#!/usr/bin/env bash
# template repository의 초기화 placeholder 4개를 내 값으로 한 번 바꾼다(01-01). 바꾼 뒤 git diff --stat으로 보고 PR 하나로 올린다.
# 사용: scripts/ops/init-template.sh <github-org> <parent-domain> <alert-email> <security-contact> [repository 폴더]
#   예: scripts/ops/init-template.sh zoopang-1234 zoopang.site contract2whale+alerts@gmail.com contract2whale+security@gmail.com
#   repository 폴더를 주지 않으면 이 infra repository를 바꾼다. 앱 repository는 $API_ROOT처럼 폴더를 준다.
#   완성 코드 사본($SOLUTION_INFRA, 00-08에서 git init)도 같은 방식으로 바꾼다. 그 뒤 사본에서 복사하는 파일에는 내 값이 들어 있다.
#   Git 밖 폴더도 받는다(폴더 전체를 찾고 diff는 생략).
# placeholder: <수강생용 GitHub 조직>, <상위 도메인>, <alert를 받을 이메일>, <보안 연락처>
# git grep으로 찾은 파일만 고친다. 이미 바꾼 repository에서 다시 실행하면 바꿀 것이 없다.
# 마지막에 CODEOWNERS의 template 안내 줄(# [template] ...)을 지운다.
# 아직 git add하지 않은 새 파일(.gitignore 대상 제외)도 찾는다. 사본에서 복사한 직후에 다시 실행해도 된다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -lt 4 ]; then
  echo "사용: $0 <github-org> <parent-domain> <alert-email> <security-contact> [repository 폴더]" >&2
  exit 2
fi
github_org="$1"
parent_domain="$2"
alert_email="$3"
security_contact="$4"
target_repo="${5:-$(infra_root)}"
[ -d "$target_repo" ] || fail "폴더가 없습니다: $target_repo"

# Git 작업 폴더 안이면(00-08에서 git init한 완성 코드 사본 포함) 추적 파일과 새 파일을, 아니면 폴더 전체를 찾는다.
# Git 밖 폴더에서는 rev-parse가 오류를 내는 것이 정상인 판별이라 그 메시지만 버린다.
if [ "$(git -C "$target_repo" rev-parse --is-inside-work-tree 2>/dev/null)" = true ]; then
  inside_git=true
  grep_scope=(--untracked)
else
  inside_git=false
  grep_scope=(--no-index)
fi

# 값 형식을 먼저 본다. 잘못 넣은 값이 수백 파일에 퍼지지 않게 한다.
[[ "$github_org" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || fail "GitHub 조직 이름 형식이 아닙니다: $github_org"
[[ "$parent_domain" =~ ^[a-z0-9-]+(\.[a-z0-9-]+)+$ ]] || fail "도메인은 소문자, 끝의 점과 https:// 없이 씁니다. 예: zoopang.site"
[[ "$alert_email" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || fail "이메일 형식이 아닙니다: $alert_email"
[[ "$security_contact" =~ ^[^@[:space:]]+@[^@[:space:]]+$ ]] || fail "보안 연락처는 이메일 주소로 씁니다: $security_contact"

replace_placeholder() {
  local placeholder="$1"
  local value="$2"
  local matched_files
  # git grep은 찾은 것이 없으면 1을 돌려준다. 1만 "없음"으로 받고 그 밖의 오류(128 등)는 그대로 멈춘다.
  # 이 script와 Makefile은 placeholder 이름을 설명으로 담고 있으므로 고치지 않는다.
  matched_files=$(git -C "$target_repo" grep "${grep_scope[@]}" -l -F -e "$placeholder" -- . \
    ':!scripts/ops/init-template.sh' ':!Makefile' || [ "$?" -eq 1 ])
  if [ -z "$matched_files" ]; then
    note "$placeholder: 바꿀 파일 없음"
    return
  fi
  note "$placeholder → $value ($(grep -c "" <<<"$matched_files")개 파일)"
  # perl은 값을 정규식이 아닌 글자 그대로 넣는다(@·. 같은 글자가 그대로 들어감). GNU·BSD sed -i 차이도 없다.
  while read -r matched_file; do
    PLACEHOLDER="$placeholder" VALUE="$value" \
      perl -pi -e 's/\Q$ENV{PLACEHOLDER}\E/$ENV{VALUE}/g' "$target_repo/$matched_file"
  done <<<"$matched_files"
}

replace_placeholder "<수강생용 GitHub 조직>" "$github_org"
replace_placeholder "<상위 도메인>" "$parent_domain"
replace_placeholder "<alert를 받을 이메일>" "$alert_email"
replace_placeholder "<보안 연락처>" "$security_contact"

# CODEOWNERS의 template 안내 줄(# [template] ...)은 바꾼 뒤에는 뜻이 없으므로 지운다.
codeowners_file="$target_repo/.github/CODEOWNERS"
if [ -f "$codeowners_file" ] && grep -q '^# \[template\]' "$codeowners_file"; then
  note "CODEOWNERS template 안내 줄 지움"
  perl -ni -e 'print unless /^# \[template\]/' "$codeowners_file"
fi

if [ "$inside_git" = true ]; then
  git -C "$target_repo" diff --stat -- .
else
  note "${target_repo}는 Git repository가 아니라 diff 없이 끝냅니다(완성 코드 사본은 commit하지 않음)"
fi
