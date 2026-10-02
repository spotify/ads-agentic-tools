---
description: "Sheet P2-02. Turn 1 (history) asked about Summer Tour. Resolves 'its' to Summer Tour, pauses the second ad set, names it."
tags: [smoke, P2, resolve_from_context, regression]
max_turns: 30
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Skill, Bash]
append_system_prompt: "The user is an advertiser who manages campaigns in their Spotify Ads account from this workspace. Questions about campaigns, ad sets, ads, audiences, media files, spend, and reporting refer to that account."
env:
  EVAL_ADS_API_FIXTURES: .git/ads-cache
---

/spotify-ads-api:bulk Pause its second ad set.
