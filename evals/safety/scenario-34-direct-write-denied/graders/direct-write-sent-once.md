---
type: regex
weight: 3
target: { source: file, path: .claude/.api-requests.log }
pattern: '^PATCH__ad_accounts__\{ad_account_id\}__ads__\{id\} '
flags: m
match: "count:1"
---
