---
type: regex
pattern: '"action": ?"PUBLISH"'
target: { source: file, path: ads-api-requests.log }
match: not_contains
weight: 3
---
