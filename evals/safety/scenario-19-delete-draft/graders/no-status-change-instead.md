---
type: regex
target: { source: file, path: .claude/.api-requests.log }
pattern: '^PATCH__'
flags: m
match: not_contains
---
