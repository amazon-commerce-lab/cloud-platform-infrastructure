#!/usr/bin/env bash
# Kyverno 정책 test(pass·fail fixture)를 Dev·Prod 모두 돌린다. PR의 kyverno-test check와 같다.
# 사용: scripts/ops/kyverno-test.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(infra_root)"

# Kyverno 정책은 14-12부터 생긴다. 08장에서 PR 검사를 가져온 뒤 그 전까지는 건너뛴다.
if [ ! -d gitops/platform/kyverno/tests/dev ]; then
  note "gitops/platform/kyverno/tests/dev가 아직 없어 Kyverno test를 건너뜁니다"
  exit 0
fi
kyverno test gitops/platform/kyverno/tests/dev

# Prod 정책 test는 Prod 등록 목록(17장)이 생긴 뒤부터 돈다.
if [ -d gitops/clusters/prod ]; then
  kyverno test gitops/platform/kyverno/tests/prod
else
  note "gitops/clusters/prod가 아직 없어 Prod Kyverno test를 건너뜁니다"
fi
