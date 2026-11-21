---
type: regex
weight: 2
# Raw HTTP statuses and API error codes stay out of replies. A 4xx/5xx number
# right after an ISO currency code is an amount ("USD 400"), not a status, so
# only those codes are exempt; "API 403 error" still fails.
pattern: 'HTTP|status (code )?\d{3}|(?<!(?:USD|EUR|GBP|JPY|KRW|AUD|CAD|BRL|MXN|SEK|NOK|DKK|CHF|INR|SGD|NZD|PLN|IDR|ZAR) )\b[45]\d\d (error|response)|ERR-\d+'
match: not_contains
---
