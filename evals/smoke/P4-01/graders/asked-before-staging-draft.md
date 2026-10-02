---
type: regex
target: { source: file, path: ads-api-requests.log }
pattern: '^(POST|PATCH|PUT|DELETE)__'
flags: m
match: not_contains
---
