#!/usr/bin/env bash
# Prometheus rule 문법 검사와 rule 단위 시험(promtool). PR의 rules-test check가 이 script를 그대로 부른다(13-16).
# 사용: scripts/ops/rules-test.sh [작업 폴더]
#   작업 폴더를 주지 않으면 work/rules-test(.gitignore 대상)에 rule 파일을 꺼낸다. CI는 $RUNNER_TEMP/rule-tests를 준다.
# promtool이 PATH에 있으면 그것을, 없으면 CI와 같은 Prometheus image의 promtool을 docker로 쓴다.
# 아직 만들지 않은 rule 파일(예: 13장에서는 16장 commerce-slo, 17장 values-prod.yaml)은 건너뛴다.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$(infra_root)"

# CI와 로컬이 같은 promtool 버전을 쓴다. kube-prometheus-stack chart의 Prometheus 버전과 맞춘다.
prometheus_image="quay.io/prometheus/prometheus:v3.14.0"
values_dir=gitops/platform/kube-prometheus-stack
work_dir="${1:-$(infra_root)/work/rules-test}"
mkdir -p "$work_dir"
work_dir=$(cd "$work_dir" && pwd)
rule_files=()
test_files=()

# values 파일의 additionalPrometheusRulesMap 항목 하나를 rule 파일로 꺼낸다.
# 예: extract_rules values-prod.yaml aiops-health-rules prod-aiops-health-rules → prod-aiops-health-rules.rules.yaml
extract_rules() {
  local values_file="$values_dir/$1"
  local rule_name="$2"
  local output_name="$3"
  if [ ! -f "$values_file" ] ||
    [ "$(RULE_NAME="$rule_name" yq '.additionalPrometheusRulesMap | has(strenv(RULE_NAME))' "$values_file")" != true ]; then
    note "$1에 ${rule_name}이 아직 없어 건너뜁니다"
    return
  fi
  RULE_NAME="$rule_name" yq -e '.additionalPrometheusRulesMap[strenv(RULE_NAME)]' "$values_file" \
    >"$work_dir/$output_name.rules.yaml"
  rule_files+=("$output_name.rules.yaml")
}

# values의 rule과 rules/ 원본이 같은지 본다. 다르면 diff를 보이고 멈춘다.
compare_with_source() {
  local rule_name="$1"
  if [ ! -f "$values_dir/rules/$rule_name.rules.yaml" ]; then
    return
  fi
  yq -o=json '.' "$values_dir/rules/$rule_name.rules.yaml" | jq -S . >"$work_dir/$rule_name-source.json"
  yq -o=json '.' "$work_dir/$rule_name.rules.yaml" | jq -S . >"$work_dir/$rule_name-values.json"
  diff -u "$work_dir/$rule_name-source.json" "$work_dir/$rule_name-values.json"
}

promtool_run() {
  if command -v promtool >/dev/null; then
    (cd "$work_dir" && promtool "$@")
  else
    docker run --rm --network none -v "$work_dir:/w:ro" -w /w --entrypoint promtool "$prometheus_image" "$@"
  fi
}

for rule_name in platform-alerts telemetry-alerts commerce-slo commerce-coverage commerce-history control-plane-survival; do
  extract_rules values.yaml "$rule_name" "$rule_name"
done
extract_rules values-dev.yaml dev-web-dev dev-web-dev
# 18-15 장애 탐지 rule과 18-16 AIOps 자체 감시 rule. Robusta alert_allowlist의 이름 대부분이 여기서 나온다.
extract_rules values-dev.yaml aiops-drill-rules aiops-drill-rules
extract_rules values-dev.yaml aiops-health-rules dev-aiops-health-rules
# Prod로 승격한 운영 rule과 Prod AIOps 자체 감시 rule
extract_rules values-prod.yaml prod-operational-rules prod-operational-rules
extract_rules values-prod.yaml aiops-health-rules prod-aiops-health-rules

for rule_name in control-plane-survival commerce-history; do
  if [ -f "$work_dir/$rule_name.rules.yaml" ]; then
    compare_with_source "$rule_name"
  fi
done

# 시험 파일은 대상 rule 파일이 있을 때만 돈다. 예: tests/commerce-slo.test.yaml → commerce-slo.rules.yaml
for test_path in "$values_dir"/tests/*.test.yaml; do
  test_name=$(basename "$test_path" .test.yaml)
  if [ -f "$work_dir/$test_name.rules.yaml" ]; then
    cp "$test_path" "$work_dir/"
    test_files+=("$test_name.test.yaml")
  fi
done

note "promtool check rules (${#rule_files[@]}개 파일)"
promtool_run check rules "${rule_files[@]}"
if [ "${#test_files[@]}" -gt 0 ]; then
  note "promtool test rules (${#test_files[@]}개 파일)"
  promtool_run test rules "${test_files[@]}"
fi
