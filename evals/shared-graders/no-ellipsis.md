---
type: regex
# Flags any ellipsis followed by whitespace or the end of a line, including
# mid-sentence ("Pulling the report... spend was"). Exempt: an ellipsis inside a
# double-quoted name ("Wait... for me", "Coming soon..."), detected by an odd
# number of quotes after it on the line, and a table cell ending in an
# ellipsis ("| abc... |").
pattern: '(…|\.\.\.)(?=\s|$)(?!\s*\|)(?=(?:[^"\n]*"[^"\n]*")*[^"\n]*$)'
flags: m
match: not_contains
---
