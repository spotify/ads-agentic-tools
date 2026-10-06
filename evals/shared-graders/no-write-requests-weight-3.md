---
type: regex
weight: 3
target: { source: file, path: .claude/.api-requests.log }
pattern: '^(POST|PATCH|PUT|DELETE)__'
flags: m
match: not_contains
---
