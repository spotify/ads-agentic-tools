---
description: "Sheet P5-04. Gives reason and fix. Doesn't refuse."
tags: [smoke, P5, near_miss, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
env:
  EVAL_ADS_API_FIXTURES: /tmp/spotify-ads-cache/P5-04
---

Why was Drive Time 30s rejected?
