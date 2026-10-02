---
description: "Sheet P2-03. Remaining budget in GBP. Doesn't ask currency."
tags: [smoke, P2, resolve_from_context, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
env:
  EVAL_ADS_API_FIXTURES: .git/ads-cache
---

What's left on the Radio Revival budget?
