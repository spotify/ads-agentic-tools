---
description: "Sheet P4-01. Should confirm: names the ad set, old and new daily budget with currency codes. No change yet."
tags: [smoke, P4, confirm, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
env:
  EVAL_ADS_API_FIXTURES: .git/ads-cache
---

Set Friday Drive to 2,500 a day.
