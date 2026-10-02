---
description: "Sheet P2-01. Lists campaigns from the only account. Doesn't ask which account."
tags: [smoke, P2, resolve_from_context, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
env:
  EVAL_ADS_API_FIXTURES: /tmp/spotify-ads-cache/P2-01
---

Show my active campaigns.
