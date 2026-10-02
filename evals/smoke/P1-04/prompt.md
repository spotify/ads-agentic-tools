---
description: "Sheet P1-04. States status as Pending approval. No raw enum. (Sheet uses PENDING_APPROVAL, which the API only returns for ad sets and ads; kept as written pending design.)"
tags: [smoke, P1, lookup_easy_edit, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
env:
  EVAL_ADS_API_FIXTURES: .ads-api
---

Is Podcast Launch live yet?
