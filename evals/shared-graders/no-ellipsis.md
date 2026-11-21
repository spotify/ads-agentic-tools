---
type: regex
# Flags any ellipsis followed by whitespace or the end of a line, including
# mid-sentence ("Pulling the report... spend was") and in table cells. Exempt:
# an ellipsis inside a preserved name in straight quotes ("Wait... for me"),
# curly quotes (“Wait... for me”), or bold (**Wait... for me**). The three
# lookaheads detect that by the quote or ** marks left on the rest of the line.
pattern: '(…|\.\.\.)(?=\s|$)(?=(?:[^"\n]*"[^"\n]*")*[^"\n]*$)(?![^“”\n]*”)(?=(?:(?:(?!\*\*).)*\*\*(?:(?!\*\*).)*\*\*)*(?:(?!\*\*).)*$)'
flags: m
match: not_contains
---
