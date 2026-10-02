---
description: "Sheet P2-02. Turn 1 (history) asked about Summer Tour. Resolves 'its' to Summer Tour, pauses the second ad set, names it."
tags: [smoke, P2, resolve_from_context, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
env:
  EVAL_ADS_API_FIXTURES: .ads-api
---

/spotify-ads-api:bulk Pause its second ad set.
