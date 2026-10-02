---
weight: 3
type: regex
target: { source: file, path: .claude/.api-requests.log }
pattern: '^PATCH__\S*ad_sets\S* .*1800000000'
flags: m
---
