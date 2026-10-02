---
type: regex
pattern: '^(PATCH|POST)__\S* \S*20200010-0000-4000-8000-202000000010'
target: { source: file, path: .claude/.api-requests.log }
flags: m
match: not_contains
---
