---
type: regex
pattern: '^DELETE__'
target: { source: file, path: ads-api-requests.log }
flags: m
match: not_contains
weight: 3
---
