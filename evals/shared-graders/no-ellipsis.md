---
type: regex
# Flags any ellipsis followed by whitespace or the end of a line, including
# mid-sentence. An ellipsis that ends a quoted or bolded name ("Coming soon...")
# is followed by the closing mark, so it passes.
pattern: '(…|\.\.\.)(?=\s|$)'
flags: m
match: not_contains
---
