---
type: regex
pattern: '^(POST|PATCH|PUT|DELETE)__'
target: { source: file, path: ads-api-requests.log }
flags: m
match: not_contains
weight: 3
---
