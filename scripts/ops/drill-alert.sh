#!/usr/bin/env bash
# 점검 결과 alert DrillCheckFailed를 Dev Alertmanager에 넣는다(13-12, 18-15). 실제 alert와 같은 경로(Slack·AI 1차 조사)를 탄다.
# 사용: scripts/ops/drill-alert.sh <check> <namespace> <summary> [evidence] [severity]
#   예: scripts/ops/drill-alert.sh argocd-offboarding argocd "회수 기한이 지난 test user가 Argo CD에 아직 로그인할 수 있음"
#   severity 기본값은 warning(SNS·Slack). 13-12의 oncall 경로 시험은 critical(PagerDuty)로 넣는다.
# Alertmanager로 들어오는 연결은 alert를 보내는 쪽의 ServiceAccount로 제한되어 있어 Pod 안의 amtool로 넣는다.
# 권한: Dev JIT dev-admin-jit, context commerce-dev-eks-admin. evidence에 credential·token을 넣지 않는다(Slack과 모델로 간다).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

if [ "$#" -lt 3 ]; then
  echo "사용: $0 <check> <namespace> <summary> [evidence] [severity]" >&2
  exit 2
fi
check_name="$1"
check_namespace="$2"
check_summary="$3"
check_evidence="${4:-}"
check_severity="${5:-warning}"
case "$check_severity" in
  warning | critical | info) ;;
  *) fail "SEVERITY는 warning, critical, info 중 하나입니다. 받은 값: '$check_severity'" ;;
esac
context_name=$(context_for_access dev admin)

# alert는 1시간 뒤 저절로 풀린다. GNU date(devcontainer)와 BSD date(macOS)의 옵션이 달라 둘 다 받는다.
# 예: 2026-11-06T13:00:00Z
if date --version >/dev/null 2>&1; then
  ends_at=$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)
else
  ends_at=$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ)
fi

annotations=(--annotation=summary="$check_summary")
if [ -n "$check_evidence" ]; then
  annotations+=(--annotation=evidence="$check_evidence")
fi

kubectl --context "$context_name" -n monitoring exec alertmanager-kube-prometheus-stack-alertmanager-0 -c alertmanager -- \
  amtool alert add --alertmanager.url=http://127.0.0.1:9093 --end="$ends_at" \
  alertname=DrillCheckFailed source=drill-check check="$check_name" namespace="$check_namespace" \
  severity="$check_severity" environment=dev \
  "${annotations[@]}"

note "DrillCheckFailed($check_name, $check_severity) 추가. 해제 예정 $ends_at"
