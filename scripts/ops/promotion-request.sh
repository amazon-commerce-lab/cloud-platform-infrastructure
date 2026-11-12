#!/usr/bin/env bash
# verify-dev-release.yml(PROMOTION) run의 검증 기록에서 승격 요청 파일을 만든다. 값을 run summary에서 손으로 옮기지 않는다.
# 사용: scripts/ops/promotion-request.sh <run ID 또는 run URL>
#   예: scripts/ops/promotion-request.sh https://github.com/zoopang-1234/cloud-platform-infrastructure/actions/runs/123
# 결과: ci/release/promotion-requests/<release_id>.json 한 파일. git diff로 보고 PR로 올린다(merge 뒤 promote workflow를 실행).
#   예: {"target": "commerce-api", "subject": "sha256:...", "release_id": "commerce-api-...", "content_commit": "<40자리>",
#        "dev_attestation_digest": "sha256:..."}
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -ne 1 ]; then
  echo "사용: $0 <run ID 또는 run URL>" >&2
  exit 2
fi
run_id="${1##*/}"
[[ "$run_id" =~ ^[0-9]+$ ]] || fail "run ID는 숫자입니다. 받은 값: $1"
cd "$(infra_root)"

# 작업 폴더는 /work/(.gitignore)다. 같은 run을 다시 받으면 이전 내용을 덮어쓰지 않게 run마다 폴더를 나눈다.
download_dir="work/promotion-evidence/$run_id"
mkdir -p "$download_dir"
gh run download "$run_id" --pattern 'dev-evidence-*' --dir "$download_dir"

completion_file=$(find "$download_dir" -name completion.json -print -quit)
ledger_file=$(find "$download_dir" -path '*/sealed/*' -name ledger.json -print -quit)
[ -n "$completion_file" ] || fail "completion.json이 없습니다. verifier run이 끝까지 성공했는지 봅니다: $run_id"
[ -n "$ledger_file" ] || fail "sealed/ledger.json이 없습니다. PROMOTION mode run인지 봅니다(DEV_ACCEPTANCE run은 승격 검증 기록이 아님)"
[ "$(jq -r '.promotion_eligible' "$completion_file")" = true ] || fail "promotion_eligible이 true가 아닙니다: $completion_file"

release_id=$(jq -r '.release_id' "$completion_file")
request_file="ci/release/promotion-requests/$release_id.json"
jq -n \
  --slurpfile completion "$completion_file" \
  --slurpfile ledger "$ledger_file" \
  '{target: $completion[0].results.target,
    subject: $completion[0].image.index,
    release_id: $completion[0].release_id,
    content_commit: $completion[0].content_commit,
    dev_attestation_digest: $ledger[0].attestation_digest}' > "$request_file"
note "승격 요청 파일: $request_file (run $run_id). git add 뒤 git diff --staged로 보고 PR로 올립니다"
