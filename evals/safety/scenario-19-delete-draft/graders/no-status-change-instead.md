---
type: regex
target: { source: file, path: ads-api-requests.log }
pattern: '^PATCH__'
flags: m
match: not_contains
---
