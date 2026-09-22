---
access_token: ""
refresh_token: ""
token_expires_at: ""
client_id: ""
auth_flow: ""
ad_account_id: ""
environment: "production"
auto_execute: false
---

# Spotify Ads API Settings

Local configuration for the spotify-ads-api plugin. Store this file at
`.codex/spotify-ads-api.local.md` on Codex, `.claude/spotify-ads-api.local.md`
on Claude, or `.agents/spotify-ads-api.local.md` on Antigravity.
Do not commit this file to version control.

## Fields

- **access_token**: Your Spotify Ads API OAuth2 bearer token.
- **refresh_token**: OAuth2 refresh token for automatic token renewal.
- **token_expires_at**: ISO 8601 timestamp when the access token expires.
- **client_id**: Your Spotify app client ID from the developer dashboard.
- **auth_flow**: `authorization_code_pkce` for OAuth or `direct_token` for a legacy direct token.
- **ad_account_id**: The UUID of the ad account to use by default.
- **environment**: `production`.
- **auto_execute**: Set to `true` to execute API calls without confirmation, `false` to preview first.

OAuth uses PKCE with the team-owned client ID. No application secret is required or stored. For direct-token mode, leave the refresh token, expiry, and client ID empty and set `auth_flow` to `direct_token`.
