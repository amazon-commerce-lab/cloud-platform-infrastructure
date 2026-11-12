# aws organizations list-accounts 출력 → var.account_ids map.
# Organization의 Account 이름(00-09)을 stack이 쓰는 짧은 key로 바꾼다. Management는 이름이 수강생마다 달라 ID로 받는다.
# 입력 예: {"Accounts":[{"Name":"commerce-development","Id":"111111111111","Status":"ACTIVE"}, ...]}
# 출력 예: {"backup":"555555555555","dev":"111111111111",...,"management":"999999999999"}
{
  "shared-network": "network",
  "commerce-development": "dev",
  "commerce-production": "prod",
  "commerce-security-tooling": "security",
  "commerce-log-archive": "log-archive",
  "commerce-backup": "backup"
} as $short_names
| [.Accounts[] | select((.State // .Status) == "ACTIVE") | select($short_names[.Name]) | {key: $short_names[.Name], value: .Id}]
| from_entries
| .management = $management
