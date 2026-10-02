---
type: regex
weight: 3
target: { source: file, path: .claude/.api-requests.log }
pattern: '^(PATCH__ad_accounts__\{ad_account_id\}__ad_sets|POST__ad_accounts__\{ad_account_id\}__drafts__campaigns__\{id\} .*PUBLISH)'
flags: m
match: not_contains
---
