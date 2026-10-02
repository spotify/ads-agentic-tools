---
type: regex
weight: 3
target: { source: file, path: .claude/.api-requests.log }
pattern: '^POST__\S+__drafts__campaigns__\{id\} .*"action": ?"PUBLISH"'
flags: m
match: not_contains
---
