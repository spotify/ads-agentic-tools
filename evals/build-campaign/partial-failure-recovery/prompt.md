---
description: Draft campaign is created but the draft ad set fails. The reply should say what was created, what failed in plain language, and offer next steps without deleting anything.
tags: [build-campaign, spike]
max_turns: 40
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Bash]
env:
  EVAL_ADS_API_FIXTURES: .git/ads-cache
---

Build an audio campaign for Joe's Pizza to drive awareness in the US, ages 25-44, starting October 5, 2026 and running through October 31. One ad set, $40 a day, restaurants category. Use the "Joes Pizza 30s spot" audio and the square companion image, call to action "Order now" to https://joespizza.example.com. The plan is approved as described, so go ahead and create it as drafts without checking back with me.
