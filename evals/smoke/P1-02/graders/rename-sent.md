---
type: regex
pattern: '^PATCH__\S*ad_sets__\{id\} .*Friday Drive'
target: { source: file, path: ads-api-requests.log }
flags: m
weight: 3
---
