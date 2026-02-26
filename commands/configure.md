---
name: configure
description: Configure Spotify Ads API credentials and preferences (access token, ad account ID, environment, auto-execute setting).
argument-hint: "[access_token] or no args for interactive setup"
allowed-tools: ["Read", "Write", "Bash", "AskUserQuestion"]
---

# Spotify Ads API Configuration

Set up or update the plugin's local settings file at `.claude/spotify-ads-api.local.md`.

## Process

1. Read the existing settings file at `.claude/spotify-ads-api.local.md` if it exists.

2. If the user provided an access token as an argument, update just that field. Otherwise, prompt the user for each setting using AskUserQuestion:
   - **access_token** (required) — Spotify Ads API OAuth2 bearer token
   - **ad_account_id** (required) — Default ad account UUID to use for API calls
   - **environment** (optional, default: sandbox) — `sandbox` or `production`
   - **auto_execute** (optional, default: false) — Whether to execute API calls automatically without confirmation

3. Write the settings file in this exact format:

```markdown
---
access_token: "<token>"
ad_account_id: "<uuid>"
environment: "sandbox"
auto_execute: false
---

# Spotify Ads API Settings

Local configuration for the spotify-ads-api plugin.
Do not commit this file to version control.
```

4. Verify the token works by making a test API call:

```bash
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer <token>" \
  "https://api-partner.spotify.com/ads-sandbox/v3/ad_accounts/<ad_account_id>"
```

5. Report the result:
   - **200**: Configuration saved and verified successfully.
   - **401/403**: Token may be invalid or expired. Settings saved but token needs updating.
   - **404**: Ad account ID may be incorrect. Settings saved but check the account ID.
   - Other errors: Report the status code and suggest troubleshooting.

## Notes

- The settings file is in `.claude/spotify-ads-api.local.md` which should be in `.gitignore`.
- If `.claude/` directory doesn't exist, create it.
- Never log or display the full access token — show only the last 8 characters for confirmation.
