#!/usr/bin/env bash
# chart·values만 바꾼 platform 구성요소의 반영 기록(platform-config-change/v1)을 만들고 검증한다(19-32).
# 사용: scripts/ops/platform-change-record.sh <dev|prod> <app> <render 파일> <기능 시험 이름> <기능 시험 결과 파일> <출력 파일> [Dev record]
#   예: scripts/ops/platform-change-record.sh dev velero ~/commerce-admin/work/VELERO-UPGRADE/render-dev-c.yaml \
#         velero-snapshot-restore ~/commerce-admin/work/VELERO-UPGRADE/dev-restore-result.txt \
#         ~/commerce-admin/work/VELERO-UPGRADE/dev-platform-change.json
#   Prod는 마지막 인자로 Dev record를 주면 그 hash를 dev_evidence_sha256에 넣는다.
# 값은 손으로 옮기지 않는다.
#   release_id·session_token  이 작업 폴더의 session 기록(work/release-session/<env>.json, make release-acquire가 씀)
#   content_commit            session item(make release-status)
#   chart                     main의 descriptor gitops/releases/<env>/platform/<app>.yaml의 chart source
#   application_uid·revision  Argo CD Application(관리용 container, JIT 관리 context)
#   images                    destination namespace에서 실행 중인 Pod의 imageID(digest)
# 관리용 container에서 실행한다. Dev는 dev-admin-jit, Prod는 prod-admin-jit 배정이 있어야 Argo CD·kubectl 조회가 된다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -lt 6 ] || [ "$#" -gt 7 ]; then
  echo "사용: $0 <dev|prod> <app> <render 파일> <기능 시험 이름> <기능 시험 결과 파일> <출력 파일> [Dev record]" >&2
  exit 2
fi
env_name="$1"
app_name="$2"
render_file="$3"
test_name="$4"
test_evidence_file="$5"
output_file="$6"
dev_record_file="${7:-}"
require_env_name "$env_name"
cd "$(infra_root)"

[ -s "$render_file" ] || fail "render 파일이 없거나 비었습니다: $render_file"
[ -s "$test_evidence_file" ] || fail "기능 시험 결과 파일이 없거나 비었습니다: $test_evidence_file"
if [ "$env_name" = prod ]; then
  [ -s "$dev_record_file" ] || fail "Prod 기록에는 Dev record 파일이 필요합니다(dev_evidence_sha256)"
fi

session_file="work/release-session/$env_name.json"
[ -f "$session_file" ] || fail "$session_file 이 없습니다. 이 작업 폴더에서 make release-acquire ENV=$env_name을 먼저 실행합니다"

# Dev·Prod 모두 대상 클러스터와 Argo CD context를 명시한다.
kube_context="commerce-$env_name-eks-admin"
argocd_args=(--kube-context "$kube_context" --argocd-context "commerce-$env_name")

content_commit=$(python3 -m ci.release.session --env "$env_name" status | awk '$1 == "content_commit:" {print $2}')
[[ "$content_commit" =~ ^[0-9a-f]{40}$ ]] || fail "session item에서 content_commit을 읽지 못했습니다. make release-status ENV=$env_name으로 session을 확인합니다"

descriptor="gitops/releases/$env_name/platform/$app_name.yaml"
[ -f "$descriptor" ] || fail "descriptor가 없습니다: $descriptor"
chart_source=$(yq -o=json '[.spec.sources[] | select(has("chart"))][0]' "$descriptor")

application_json=$(argocd app get "$app_name" "${argocd_args[@]}" -o json)
namespace=$(jq -r '.spec.destination.namespace' <<<"$application_json")
health=$(jq -r '.status.health.status' <<<"$application_json")
[ "$health" = Healthy ] || fail "$app_name Application health가 Healthy가 아닙니다: $health"

# 실행 중인 container의 imageID. containerd 표기 그대로 registry/repository@sha256:<digest>이다.
images_json=$(kubectl --context "$kube_context" -n "$namespace" get pods -o json |
  jq '[.items[] | select(.status.phase == "Running") | (.status.containerStatuses + (.status.initContainerStatuses // []))[].imageID
       | sub("^docker-pullable://"; "")] | unique')

dev_evidence_sha256=""
if [ "$env_name" = prod ]; then
  dev_evidence_sha256=$(sha256sum "$dev_record_file" | cut -d' ' -f1)
fi

jq -n \
  --slurpfile session "$session_file" \
  --arg content_commit "$content_commit" \
  --arg environment "$env_name" \
  --argjson chart_source "$chart_source" \
  --arg render_sha256 "$(sha256sum "$render_file" | cut -d' ' -f1)" \
  --argjson images "$images_json" \
  --argjson application "$application_json" \
  --arg test_name "$test_name" \
  --arg test_evidence_sha256 "$(sha256sum "$test_evidence_file" | cut -d' ' -f1)" \
  --arg dev_evidence_sha256 "$dev_evidence_sha256" \
  --argjson completed_at "$(date +%s)" \
  '{
    schema_version: "platform-config-change/v1",
    release_id: $session[0].release_id,
    content_commit: $content_commit,
    environment: $environment,
    session_token: $session[0].token,
    chart: {repository: $chart_source.repoURL, name: $chart_source.chart, version: $chart_source.targetRevision},
    render_sha256: $render_sha256,
    images: $images,
    application_uid: $application.metadata.uid,
    observed_revision: ([$application.status.sync.revisions[]? | select(test("^[0-9a-f]{40}$"))][0] // $application.status.sync.revision),
    rollout: "HEALTHY",
    functional_test: {name: $test_name, status: "PASSED", evidence_sha256: $test_evidence_sha256},
    completed_at: $completed_at
  } + (if $dev_evidence_sha256 == "" then {} else {dev_evidence_sha256: $dev_evidence_sha256} end)' \
  >"$output_file"

note "$output_file 검증"
python3 -m ci.release.validate_record --schema platform-config-change --record "$output_file"
