---
description: "Sheet P1-03. Total spend for the current month with currency code. Doesn't ask how to break it down."
tags: [smoke, P1, lookup_easy_edit, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
env:
  EVAL_ADS_API_FIXTURES: .ads-api
---

How much did we spend this month?
