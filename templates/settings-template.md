---
access_token: ""
refresh_token: ""
token_expires_at: ""
client_id: ""
client_secret: ""
ad_account_id: ""
environment: "sandbox"
auto_execute: false
---

# Spotify Ads API Settings

Local configuration for the spotify-ads-api plugin.
Do not commit this file to version control.

## Fields

- **access_token**: Your Spotify Ads API OAuth2 bearer token.
- **refresh_token**: OAuth2 refresh token for automatic token renewal.
- **token_expires_at**: ISO 8601 timestamp when the access token expires.
- **client_id**: Your Spotify app client ID from the developer dashboard.
- **client_secret**: Your Spotify app client secret.
- **ad_account_id**: The UUID of the ad account to use by default.
- **environment**: `sandbox` (testing) or `production` (live).
- **auto_execute**: Set to `true` to execute API calls without confirmation, `false` to preview first.
