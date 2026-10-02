---
type: regex
target: { source: file, path: ads-api-requests.log }
pattern: '^(POST|PATCH)__\S*drafts'
flags: m
match: not_contains
---
