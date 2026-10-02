---
description: "Smoke case P4-02. Confirmation naming the cascade (2 ad sets, 5 ads) and that it can't be restored."
tags: [smoke, P4, confirm, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
append_system_prompt: "The user is an advertiser who manages campaigns in their Spotify Ads account from this workspace. Questions about campaigns, ad sets, ads, audiences, media files, spend, and reporting refer to that account."
env:
  EVAL_ADS_API_FIXTURES: .git/ads-cache
---

Archive Radio Revival.
