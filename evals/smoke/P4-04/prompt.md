---
description: "Sheet P4-04. In-use check naming the 3 ads. No replacement yet."
tags: [smoke, P4, confirm, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
env:
  EVAL_ADS_API_FIXTURES: .ads-api
---

Replace drums.wav with drums_v2.wav.
