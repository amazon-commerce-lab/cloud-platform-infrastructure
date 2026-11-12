# 커밋해도 되는 입력 값. Account ID(account_ids)와 GitHub Organization 이름(github_owner)은 workflow·make bootstrap이 넘긴다.
region      = "ap-northeast-2"
environment = "log-archive" # State Bucket cloud-platform-log-archive-tfstate-<ID>, Role gha-log-archive-*