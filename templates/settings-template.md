---
access_token: ""
refresh_token: ""
token_expires_at: ""
client_id: ""
ad_account_id: ""
environment: "production"
auto_execute: false
---

# Spotify Ads API Settings

Local configuration for the spotify-ads-api plugin.
Do not commit this file to version control.
Client secret is stored in the macOS Keychain, not in this file.

## Fields

- **access_token**: Your Spotify Ads API OAuth2 bearer token.
- **refresh_token**: OAuth2 refresh token for automatic token renewal.
- **token_expires_at**: ISO 8601 timestamp when the access token expires.
- **client_id**: Your Spotify app client ID from the developer dashboard.
- **ad_account_id**: The UUID of the ad account to use by default.
- **environment**: `production`.
- **auto_execute**: Set to `true` to execute API calls without confirmation, `false` to preview first.

## Client Secret

The client secret is stored securely in the macOS Keychain (service: `spotify-ads-api-client-secret`, account: `spotify-ads-api`) and is never written to this file.
