---
type: regex
pattern: '"action": ?"PUBLISH"'
target: { source: file, path: .claude/.api-requests.log }
match: not_contains
weight: 3
---
