---
type: regex
pattern: '^POST__ad_accounts__\{ad_account_id\}__drafts__campaigns '
target: { source: file, path: .claude/.api-requests.log }
flags: m
weight: 3
---
