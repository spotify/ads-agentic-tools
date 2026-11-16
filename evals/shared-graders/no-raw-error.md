---
type: regex
weight: 2
# Raw HTTP statuses and API error codes stay out of replies.
pattern: 'HTTP|status (code )?\d{3}|(?<![A-Z]{3} )\b[45]\d\d (error|response)|ERR-\d+'
match: not_contains
---
