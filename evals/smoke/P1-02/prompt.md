---
description: "Sheet P1-02. Renames and confirms in one line. No confirmation prompt."
tags: [smoke, P1, lookup_easy_edit, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
env:
  EVAL_ADS_API_FIXTURES: .git/ads-cache
---

Rename Weekend Commuters to Friday Drive.
