---
type: regex
pattern: '^(POST|PATCH|PUT|DELETE)__'
target: { source: file, path: .claude/.api-requests.log }
flags: m
match: not_contains
---
