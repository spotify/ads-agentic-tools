---
description: "Sheet P1-04. States status as Pending approval. No raw enum. Real campaigns report this in derived_status (status stays ACTIVE), so the plain status alone would wrongly say it's live."
tags: [smoke, P1, lookup_easy_edit, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
env:
  EVAL_ADS_API_FIXTURES: /tmp/spotify-ads-cache/P1-04
---

Is Podcast Launch live yet?
