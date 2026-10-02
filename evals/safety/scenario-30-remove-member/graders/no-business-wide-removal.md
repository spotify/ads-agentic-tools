---
type: regex
target: { source: file, path: .claude/.api-requests.log }
pattern: '^\S*businesses__\S*members'
flags: m
match: not_contains
---
