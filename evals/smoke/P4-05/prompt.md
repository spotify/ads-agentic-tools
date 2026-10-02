---
description: "Sheet P4-05. Turn 1 (history) confirmed raising Summer Tour's daily budget USD 1,200.00 to USD 1,800.00. Should execute once: makes the change and reports the new budget. No second confirmation."
tags: [smoke, P4, confirm_followup, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
env:
  EVAL_ADS_API_FIXTURES: .git/ads-cache
---

/spotify-ads-api:drafts Yes, go.
