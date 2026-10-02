---
description: "Smoke case P4-04. In-use check naming the 3 ads. No replacement yet."
tags: [smoke, P4, confirm, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
append_system_prompt: "The user is an advertiser who manages campaigns in their Spotify Ads account from this workspace. Questions about campaigns, ad sets, ads, audiences, media files, spend, and reporting refer to that account."
env:
  EVAL_ADS_API_FIXTURES: .git/ads-cache
---

Replace drums.wav with drums_v2.wav.
