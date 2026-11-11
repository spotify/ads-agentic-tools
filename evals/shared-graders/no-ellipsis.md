---
type: regex
# Flags an ellipsis that trails off a sentence or the reply. An ellipsis inside a
# quoted or bolded name ("Coming soon...") is the name kept as is, so it passes.
pattern: '(…|\.\.\.)(?=[ \t]*$|\s+[A-Z])'
flags: m
match: not_contains
---
