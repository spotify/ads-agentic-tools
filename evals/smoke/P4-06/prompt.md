---
description: "Smoke case P4-06. Turn 1 (history) confirmed deleting draft Holiday Video. Doesn't delete. Brief close."
tags: [smoke, P4, confirm_followup, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
append_system_prompt: "The user is an advertiser who manages campaigns in their Spotify Ads account from this workspace. Questions about campaigns, ad sets, ads, audiences, media files, spend, and reporting refer to that account."
env:
  EVAL_ADS_API_FIXTURES: .git/ads-cache
---

/spotify-ads-api:drafts Actually no.
