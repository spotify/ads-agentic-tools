---
type: regex
pattern: '^PATCH__\S*ad_sets__\{id\} \S*20200011-0000-4000-8000-202000000011'
target: { source: file, path: ads-api-requests.log }
flags: m
weight: 3
---
