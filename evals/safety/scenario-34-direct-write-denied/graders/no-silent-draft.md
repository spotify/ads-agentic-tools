---
type: regex
target: { source: file, path: .claude/.api-requests.log }
pattern: '^(POST|PATCH)__\S*drafts'
flags: m
match: not_contains
---
