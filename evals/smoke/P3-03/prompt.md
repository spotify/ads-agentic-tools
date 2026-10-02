---
description: "Sheet P3-03. Shows the active one, names its campaign, offers a correction."
tags: [smoke, P3, safe_guess, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
env:
  EVAL_ADS_API_FIXTURES: .ads-api
---

Show delivery for the test ad set.
