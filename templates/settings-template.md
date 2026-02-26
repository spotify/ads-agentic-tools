---
access_token: ""
ad_account_id: ""
environment: "sandbox"
auto_execute: false
---

# Spotify Ads API Settings

Local configuration for the spotify-ads-api plugin.
Do not commit this file to version control.

## Fields

- **access_token**: Your Spotify Ads API OAuth2 bearer token.
- **ad_account_id**: The UUID of the ad account to use by default.
- **environment**: `sandbox` (testing) or `production` (live).
- **auto_execute**: Set to `true` to execute API calls without confirmation, `false` to preview first.
