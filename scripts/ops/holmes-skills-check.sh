#!/usr/bin/env bash
# Holmes Skill 원본(skills/<이름>/SKILL.md)과 values-dev·values-prod의 customSkills.<이름>.content가 같은지 본다(18-12).
# 사용: scripts/ops/holmes-skills-check.sh
#   make gitops-check(PR의 gitops-render-all)가 부른다. 다르면 어느 파일의 어느 Skill인지 출력하고 실패한다.
# 고칠 때는 SKILL.md를 바꾸고 두 values의 같은 key에 그대로 붙여 넣는다. yq -i로 쓰면 values 파일 전체의
# 들여쓰기·주석이 바뀌어 리뷰가 어려워지므로 이 script는 비교만 한다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(infra_root)"

holmes_dir=gitops/platform/holmes
# Holmes는 18-10에서 생긴다. 그 전에는 비교할 것이 없다.
if [ ! -d "$holmes_dir/skills" ]; then
  note "$holmes_dir/skills가 아직 없어 Skill 비교를 건너뜁니다"
  exit 0
fi

mismatches=0
for skill_file in "$holmes_dir"/skills/*/SKILL.md; do
  skill_name=$(basename "$(dirname "$skill_file")")
  for values_file in "$holmes_dir"/values-dev.yaml "$holmes_dir"/values-prod.yaml; do
    if [ ! -f "$values_file" ]; then
      continue
    fi
    same=$(SKILL_NAME="$skill_name" SKILL_FILE="$skill_file" \
      yq '.customSkills[strenv(SKILL_NAME)].content == load_str(strenv(SKILL_FILE))' "$values_file")
    if [ "$same" != true ]; then
      echo "다름: $values_file customSkills.$skill_name ≠ $skill_file" >&2
      mismatches=$((mismatches + 1))
    fi
  done
done

if [ "$mismatches" -gt 0 ]; then
  fail "Holmes Skill ${mismatches}곳이 SKILL.md와 다릅니다"
fi
note "Holmes Skill 원본과 values가 같습니다"
