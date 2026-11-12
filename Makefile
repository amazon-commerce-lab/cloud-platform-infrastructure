# 운영 반복 절차 모음. 각 target은 scripts/ops/*.sh(또는 ci.release.session)를 한 줄로 부른다.
# 목록과 사용법: make help
# ENV가 없으면 dev다. 예: make kubeconfig ENV=prod ACCESS=admin
# 같은 target을 다시 실행해도 결과가 같다(이미 있는 것은 건너뛰거나 diff가 비어 있음).

ENV ?= dev
OPS := scripts/ops

# 필요한 변수가 비어 있으면 그 target만 멈춘다. 예: $(call require,TARGET CONTENT)
require = $(foreach name,$(1),$(if $(value $(name)),,$(error $(name)= 값이 필요합니다. make help로 사용법을 봅니다)))

.DEFAULT_GOAL := help
.PHONY: help eks-tunnel kubeconfig validate gitops-check kyverno-test rules-test test render \
	bootstrap migrate-state init-template argocd-bootstrap argocd-cluster jit stack \
	db-connect db-psql drill-alert mirror-image dr-drill \
	release-acquire release-transition release-descriptor release-pin-platform release-activate release-catalog-ids release-register-pr release-status release-close promotion-request acceptance-request platform-record

help: ## target 목록
	@echo "사용: make <target> [ENV=dev|prod] [변수=값 ...]"
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {name = $$1; while (length(name) < 22) name = name " "; print "  " name $$2}' $(MAKEFILE_LIST)

# ---------- 접속 ----------

eks-tunnel: ## EKS API SSM 터널(터미널 2에서 실행한 상태로 유지). ENV=dev|prod [ACCESS=operator|viewer|admin|readonly]
	$(OPS)/eks-tunnel.sh $(ENV) $(ACCESS)

kubeconfig: ## context 만들기·server를 터널로(context마다 처음 한 번). ENV= [ACCESS=]
	$(OPS)/kubeconfig.sh $(ENV) $(ACCESS)

db-connect: ## 개인 DB 접속 터널(터미널 2). ENV=dev|prod
	$(OPS)/db-connect.sh $(ENV)

db-psql: ## op_<userName>으로 psql. ENV= [SQL=파일.sql] [ARGS="-At" 같은 psql 옵션]
	@$(OPS)/db-psql.sh $(ENV) $(ARGS) $(if $(SQL),-v ON_ERROR_STOP=1 -f $(SQL))

jit: ## JIT 관리자 배정 요청→승인 대기→SSO 재로그인. ACCOUNT= PERMISSION_SET= HOURS= TICKET= REASON=
	$(call require,ACCOUNT PERMISSION_SET HOURS TICKET REASON)
	$(OPS)/jit-request.sh $(ACCOUNT) $(PERMISSION_SET) $(HOURS) $(TICKET) "$(REASON)"

stack: ## 등록 stack 수동 실행→run 지켜보기. STACK=dev/compute/eks ACTION=plan|apply|destroy
	$(call require,STACK ACTION)
	$(OPS)/stack-run.sh $(STACK) $(ACTION)

# ---------- 로컬 검사(PR check와 같은 검사) ----------

validate: ## 저장소 전체 TFLint + Terraform fmt·init·validate. [STACK=dev/compute/eks] 없으면 바뀐 stack 전부
	$(OPS)/validate.sh $(STACK)

gitops-check: ## gitops 렌더링·필수 Application·overlay 규칙. ENV=dev|prod
	$(OPS)/gitops-check.sh $(ENV)

kyverno-test: ## Kyverno 정책 test(Dev·Prod)
	$(OPS)/kyverno-test.sh

rules-test: ## Prometheus rule 문법·단위 시험(PR rules-test와 같음). [RULES_DIR=작업 폴더]
	$(OPS)/rules-test.sh $(RULES_DIR)

test: ## tests/ 아래 Python 단위 test 전부
	$(OPS)/run-tests.sh

render: ## 등록된 Application 하나 렌더링(stdout). APP= ENV=
	$(call require,APP)
	$(OPS)/render.sh $(APP) $(ENV)

# ---------- 처음 한 번 ----------

init-template: ## 조직·도메인·이메일 placeholder 바꾸기(01-01). GITHUB_ORG= PARENT_DOMAIN= ALERT_EMAIL= SECURITY_CONTACT= [REPO_DIR=]
	$(call require,GITHUB_ORG PARENT_DOMAIN ALERT_EMAIL SECURITY_CONTACT)
	$(OPS)/init-template.sh $(GITHUB_ORG) $(PARENT_DOMAIN) $(ALERT_EMAIL) $(SECURITY_CONTACT) $(REPO_DIR)

bootstrap: ## 로컬 bootstrap plan→기록→apply(02장). ACCOUNT=management|network|dev|prod|security|log-archive|backup|github
	$(call require,ACCOUNT)
	$(OPS)/bootstrap.sh $(ACCOUNT)

migrate-state: ## bootstrap 로컬 State를 State Bucket으로(02-04). ACCOUNT=
	$(call require,ACCOUNT)
	$(OPS)/migrate-state.sh $(ACCOUNT)

argocd-bootstrap: ## Argo CD 설치·AppProject·cluster Secret·root(08-07, 17-18). ENV=
	$(OPS)/argocd-bootstrap.sh $(ENV)

argocd-cluster: ## SSM 값으로 in-cluster Secret diff→apply. ENV=
	$(OPS)/argocd-cluster.sh $(ENV)

# ---------- release session(16·17장) ----------

release-acquire: ## 검사 결과 무효화→session 잡기. TARGET= PR=<번호|branch>(또는 CONTENT=<40자리>) [MODE=] [RELEASE_ID=] ENV=
	$(call require,TARGET)
	$(if $(or $(PR),$(CONTENT)),,$(error PR= 또는 CONTENT= 값이 필요합니다. make help로 사용법을 봅니다))
	python3 -m ci.release.session --env $(ENV) acquire --target $(TARGET) $(if $(PR),--pr $(PR)) $(if $(CONTENT),--content $(CONTENT)) $(if $(MODE),--mode $(MODE)) $(if $(RELEASE_ID),--release-id $(RELEASE_ID))

release-transition: ## 다음 phase로. STATE= ENV=
	$(call require,STATE)
	python3 -m ci.release.session --env $(ENV) transition --state $(STATE)

release-descriptor: ## descriptor branch·PR→session 등록→검사. TARGET= [PR= 또는 CONTENT=, 없으면 session의 C] ENV=
	$(call require,TARGET)
	python3 -m ci.release.session --env $(ENV) descriptor --target $(TARGET) $(if $(PR),--pr $(PR)) $(if $(CONTENT),--content $(CONTENT))

release-pin-platform: ## platform descriptor(17-18은 앱 Application도) Git source를 CONTENT로 고정(16-10·17-18 한 번, 파일만 고침). CONTENT= ENV=
	$(call require,CONTENT)
	python3 -m ci.release.session --env $(ENV) pin-platform --content $(CONTENT)

release-activate: ## 첫 등록이 끝나 main에 고정된 descriptor를 catalog에서 active true로(활성화 PR, 파일만 고침). ENV=
	python3 -m ci.release.session --env $(ENV) activate

release-catalog-ids: ## catalog 맨 위의 repository·repository_id·gate_app_id·git_url을 GitHub에서 읽어 채운다(16-10 한 번, 파일만 고침)
	python3 -m ci.release.session catalog-ids

release-register-pr: ## head가 바뀐 PR 다시 등록→검사. [PR=번호|branch] 없으면 지금 branch의 PR
	python3 -m ci.release.session --env $(ENV) register-pr $(if $(PR),--pr $(PR))

release-status: ## session item 보기. ENV=
	python3 -m ci.release.session --env $(ENV) status

release-close: ## terminal session 닫기(검사 결과 무효화→삭제). ENV= [CONFIRM_RECONCILED=yes]
	python3 -m ci.release.session --env $(ENV) close $(if $(filter yes,$(CONFIRM_RECONCILED)),--confirm-reconciled)

promotion-request: ## verifier run(PROMOTION) 검증 기록으로 승격 요청 파일 만들기(파일만, PR은 직접). RUN=<run ID 또는 URL>
	$(call require,RUN)
	$(OPS)/promotion-request.sh $(RUN)

acceptance-request: ## Dev 검증 요청 파일 만들기(session 파일·AnalysisRun·migration Job을 읽음, 파일만). [CANDIDATE=] [CONTEXT=]
	python3 -m ci.release.acceptance_request $(if $(CANDIDATE),--candidate $(CANDIDATE)) $(if $(CONTEXT),--context $(CONTEXT))

platform-record: ## chart·values 변경 반영 기록 만들기·검증(19-32). ENV= APP= RENDER= TEST= EVIDENCE= OUT= [DEV_RECORD=](Prod만)
	$(call require,APP RENDER TEST EVIDENCE OUT)
	$(OPS)/platform-change-record.sh $(ENV) $(APP) $(RENDER) $(TEST) $(EVIDENCE) $(OUT) $(DEV_RECORD)

# ---------- 장애·운영 훈련 ----------

drill-alert: ## Dev Alertmanager에 DrillCheckFailed. CHECK= NAMESPACE= SUMMARY= [EVIDENCE=] [SEVERITY=warning|critical]
	$(call require,CHECK NAMESPACE SUMMARY)
	$(OPS)/drill-alert.sh $(CHECK) $(NAMESPACE) "$(SUMMARY)" "$(EVIDENCE)" $(or $(SEVERITY),warning)

mirror-image: ## 외부 image를 digest 그대로 ECR mirror/로. SOURCE=<image@sha256:...> TAG= ENV=
	$(call require,SOURCE TAG)
	$(OPS)/mirror-image.sh $(SOURCE) $(ENV) $(TAG)

dr-drill: ## Dev DR 훈련(19-22·19-23). ACTION=start|copy-to-dr|status|restore CASE= [RESOURCE=rds|ec2|ebs] [METADATA=]
	$(call require,ACTION CASE)
	scripts/dr/drill.sh $(ACTION) --case $(CASE) $(if $(RESOURCE),--resource $(RESOURCE)) $(if $(METADATA),--metadata $(METADATA))
