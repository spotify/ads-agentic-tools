---
name: configure
description: Configure Spotify Ads API credentials via OAuth 2.0 or direct token. Sets up authentication, ad account, environment, and execution preferences.
argument-hint: "[oauth | manual | token <access_token>]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "AskUserQuestion"]
---

# Spotify Ads API Configuration

Set up or update the plugin's local settings file at `.claude/spotify-ads-api.local.md`.

## Modes

Parse the user's argument to determine the configuration mode:

### `oauth` (default if no argument)

Full OAuth 2.0 authorization flow with automatic token refresh.

1. Read existing settings from `.claude/spotify-ads-api.local.md` if it exists.

2. Prompt the user for OAuth credentials using AskUserQuestion:
   - **client_id** (required) — Spotify app client ID from the developer dashboard
   - **client_secret** (required) — Spotify app client secret

3. Attempt the automated OAuth flow by running the helper script:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/configure/scripts/oauth-flow.py" \
  --client-id "<client_id>" \
  --client-secret "<client_secret>"
```

If `python3` is not available, try `uv run`:

```bash
uv run "${CLAUDE_PLUGIN_ROOT}/skills/configure/scripts/oauth-flow.py" \
  --client-id "<client_id>" \
  --client-secret "<client_secret>"
```

4. If Python is not available at all, fall back to the **manual** flow (see below).

5. Parse the JSON output from the script:
   ```json
   {"access_token": "...", "refresh_token": "...", "expires_in": 3600}
   ```

6. Calculate `token_expires_at` as the current time + `expires_in` seconds, formatted as ISO 8601.

7. Prompt for remaining settings:
   - **ad_account_id** (required) — Try fetching the list from `GET /ad_accounts` using the new token and let the user select, or ask them to paste it
   - **environment** (optional, default: sandbox) — `sandbox` or `production`
   - **auto_execute** (optional, default: false) — Whether to execute API calls without confirmation

8. Write the settings file (see Settings File Format below).

9. Verify with a test API call using the chosen environment's base URL:
```bash
# sandbox:    https://api-partner.spotify.com/ads-sandbox/v3
# production: https://api-partner.spotify.com/ads/v3
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer <token>" \
  "$BASE_URL/ad_accounts/<ad_account_id>"
```

### `manual`

Manual OAuth flow for environments where the automated script cannot run.

1. Prompt for **client_id** and **client_secret** using AskUserQuestion.

2. Display the authorization URL for the user to open in their browser:
   ```
   https://accounts.spotify.com/authorize?client_id=<CLIENT_ID>&response_type=code&redirect_uri=http://127.0.0.1:8080/callback
   ```

3. Instruct the user to:
   - Open the URL in their browser
   - Authorize the application
   - Copy the full redirect URL from the browser address bar (it will show an error page since no server is running, but the URL contains the code)

4. Ask the user to paste the redirect URL, then extract the `code` parameter from it.

5. Exchange the code for tokens:
```bash
curl -s -X POST "https://accounts.spotify.com/api/token" \
  -H "Authorization: Basic $(echo -n '<client_id>:<client_secret>' | base64)" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code&code=<CODE>&redirect_uri=http://127.0.0.1:8080/callback"
```

6. Parse the response for `access_token`, `refresh_token`, and `expires_in`.

7. Continue from step 6 of the `oauth` flow (calculate expiry, prompt for settings, write file, verify).

### `token <access_token>`

Legacy direct token mode for users who already have an access token.

1. Accept the access token from the argument.

2. Warn the user: "Direct token mode — this token will expire in ~1 hour with no automatic refresh. For auto-refresh, re-run with `/spotify-ads-api:configure oauth` using your client credentials."

3. Read existing settings or prompt for:
   - **ad_account_id** (required)
   - **environment** (optional, default: sandbox)
   - **auto_execute** (optional, default: false)

4. Write the settings file with the token but without refresh credentials. Set `token_expires_at` to empty.

5. Verify with a test API call.

## Settings File Format

Write `.claude/spotify-ads-api.local.md` in this exact format:

```markdown
---
access_token: "<token>"
refresh_token: "<refresh_token>"
token_expires_at: "<ISO 8601 timestamp>"
client_id: "<client_id>"
client_secret: "<client_secret>"
ad_account_id: "<uuid>"
environment: "sandbox"
auto_execute: false
---

# Spotify Ads API Settings

Local configuration for the spotify-ads-api plugin.
Do not commit this file to version control.
```

For the `token` mode, leave `refresh_token`, `token_expires_at`, `client_id`, and `client_secret` as empty strings.

## Verification Results

Report the test API call result:
- **200**: Configuration saved and verified successfully.
- **401/403**: Token may be invalid or expired. Settings saved but token needs updating.
- **404**: Ad account ID may be incorrect. Settings saved but check the account ID.
- Other errors: Report the status code and suggest troubleshooting.

## Security Notes

- The settings file is in `.claude/spotify-ads-api.local.md` which is gitignored via `.claude/*.local.md`.
- If `.claude/` directory doesn't exist, create it.
- Never log or display the full access token or client_secret — show only the last 8 characters for confirmation.
- OAuth credentials are stored only in the gitignored settings file and never committed.
