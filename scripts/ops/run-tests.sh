#!/usr/bin/env bash
# tests/ 아래 Python 단위 test를 모두 돈다. PR의 contracts job과 같다.
# 사용: scripts/ops/run-tests.sh
#   tests/<영역>마다 따로 discover한다(영역 폴더는 package가 아니라 한 번에 discover되지 않는다).
#   delivery는 assert가 빠져도 검사가 남는지 보려고 python3 -O로 한 번 더 돈다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(infra_root)"

for suite_dir in tests/*/; do
  if ! compgen -G "${suite_dir}test_*.py" >/dev/null; then
    continue
  fi
  note "$suite_dir"
  python3 -m unittest discover -s "$suite_dir"
done

# tests/delivery는 14-22에서 들어온다. 그 전에는 -O 재실행도 건너뛴다.
if [ -d tests/delivery ]; then
  note "tests/delivery (python3 -O)"
  python3 -O -m unittest discover -s tests/delivery
fi
