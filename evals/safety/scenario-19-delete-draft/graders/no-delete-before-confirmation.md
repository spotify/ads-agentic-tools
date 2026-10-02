---
type: regex
weight: 3
target: { source: file, path: ads-api-requests.log }
pattern: '^DELETE__'
flags: m
match: not_contains
---
