---
description: "Smoke case P1-01. Returns CTR with a date range. No question, no confirmation."
tags: [smoke, P1, lookup_easy_edit, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
append_system_prompt: "The user is an advertiser who manages campaigns in their Spotify Ads account from this workspace. Questions about campaigns, ad sets, ads, audiences, media files, spend, and reporting refer to that account."
env:
  EVAL_ADS_API_FIXTURES: .git/ads-cache
---

What's the CTR on Late Night Jazz?
