#!/usr/bin/env bash
# make target 하나가 실제로 실행하는 명령과 단계를 보여 준다. 아무것도 실행하지 않는다.
# 사용: scripts/ops/explain.sh <target>   (make explain TARGET=<target>)
#   1. Makefile에서 target의 설명(## 뒤)과 실행 줄(recipe)을 출력한다.
#   2. 실행 줄이 부르는 scripts/ops/*.sh 내용을 주석과 함께 그대로 출력한다.
#   3. 그 script가 사용하는 lib.sh 함수의 본문도 출력한다.
# 설명 문서를 따로 두지 않고 실제 코드를 출력하므로, script를 고치면 설명도 함께 바뀐다.
# 터미널에 출력할 때만 제목·주석·주요 명령에 색을 넣는다. 파이프·파일로 보내거나 NO_COLOR를 설정하면 색 없이 출력한다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -ne 1 ]; then
  echo "사용: $0 <target>   예: $0 migrate-state" >&2
  exit 2
fi
target_name="$1"
repo_root="$(infra_root)"
makefile="$repo_root/Makefile"
ops_dir="$repo_root/scripts/ops"

grep -qE "^${target_name}:" "$makefile" || fail "Makefile에 '${target_name}' target이 없습니다. make help로 목록을 확인합니다."

explain_target() {
  # 1. target 설명과 실행 줄. $(OPS)는 실제 경로로 바꿔 보여 준다.
  local description recipe scripts script_path function_name
  description=$(awk -v name="$target_name" 'index($0, name ":") == 1 { split($0, parts, "## "); print parts[2]; exit }' "$makefile")
  recipe=$(awk -v name="$target_name" '
    index($0, name ":") == 1 { inside = 1; next }
    inside && /^\t/ { sub(/^\t/, ""); print; next }
    inside { exit }
  ' "$makefile" | sed 's#\$(OPS)#scripts/ops#g')

  echo "== make ${target_name}"
  echo "설명: ${description}"
  echo
  echo "== Makefile 실행 줄"
  echo "$recipe"

  # 2. 실행 줄이 부르는 script. awk는 찾는 경로가 없어도 0으로 끝나므로 python 모듈만 부르는 target도 아래 안내까지 진행한다.
  scripts=$(echo "$recipe" | awk '{
    while (match($0, /scripts\/ops\/[a-z0-9-]+\.sh/)) {
      print substr($0, RSTART, RLENGTH)
      $0 = substr($0, RSTART + RLENGTH)
    }
  }' | sort -u)
  if [ -z "$scripts" ]; then
    echo
    echo "(scripts/ops script를 부르지 않는 target입니다. 위 실행 줄이 전체 동작입니다.)"
    return 0
  fi

  for script_path in $scripts; do
    echo
    echo "== ${script_path}"
    sed '1{/^#!/d;}' "$repo_root/$script_path"

    # 3. script가 부르는 lib.sh 함수 본문. 함수 이름이 script 안에 나오는 것만 출력한다.
    for function_name in $(grep -oE '^[a-z_]+\(\) \{' "$ops_dir/lib.sh" | sed 's/() {//'); do
      if grep -qwE "$function_name" "$repo_root/$script_path"; then
        echo
        echo "-- lib.sh: ${function_name}"
        awk -v name="$function_name" '
          index($0, name "() {") == 1 { inside = 1 }
          inside { print }
          inside && /^}/ { exit }
        ' "$ops_dir/lib.sh"
      fi
    done
  done
}

# 색 입히기. 제목(==)은 청록, lib.sh 함수(--)는 자주, 주석은 초록, 설명 줄은 굵게, 주요 명령은 노랑으로 표시한다.
colorize() {
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    awk -v heading=$'\033[1;36m' -v library=$'\033[1;35m' -v comment=$'\033[32m' \
      -v bold=$'\033[1m' -v command=$'\033[33m' -v reset=$'\033[0m' '
      /^== /               { print heading $0 reset; next }
      /^-- lib\.sh: /      { print library $0 reset; next }
      /^설명: /            { print bold $0 reset; next }
      /^[[:space:]]*#/     { print comment $0 reset; next }
      {
        gsub(/(^|[ ($|])(terraform|aws|gh|kubectl|helm|argocd|git|jq|make) /, command "&" reset)
        print
      }'
  else
    cat
  fi
}

explain_target | colorize
