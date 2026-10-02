---
type: regex
pattern: '^(PATCH|PUT|DELETE)__ad_accounts__\{ad_account_id\}__(campaigns|ad_sets|ads|audiences|assets)\b|\"action\": ?\"PUBLISH\"'
target: { source: file, path: ads-api-requests.log }
flags: m
match: not_contains
weight: 3
---
