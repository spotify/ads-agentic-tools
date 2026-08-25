---
name: configure
description: Configure Spotify Ads API credentials via OAuth 2.0 with PKCE or a direct token. Sets up authentication, ad account, and execution preferences.
argument-hint: "[oauth [client_id] | token <access_token>]"
allowed-tools: ["Read", "Write", "Edit", "Bash", "AskUserQuestion"]
---

# Spotify Ads API Configuration

Set up or update the plugin's local settings file for the active platform.

## Modes

### `oauth [client_id]` (default)

Use Authorization Code with PKCE (`S256`). The client ID belongs to the user's
team and determines client-level attribution, quotas, and rate-limit isolation.
Never substitute a plugin-global client ID; this plugin does not provide one.

**Prerequisites**

- A team administrator has created or selected a Spotify Developer application,
  enabled the Ads API, completed applicable Ads API authorization steps, and
  registered `http://127.0.0.1:8080/callback` exactly.
- Python 3.8+ or `uv` is available for the standard-library PKCE helper.

1. Choose the active settings file:
   - Codex: `.codex/spotify-ads-api.local.md`
   - Claude: `.claude/spotify-ads-api.local.md`
   - Antigravity: `.agents/spotify-ads-api.local.md`

   Read that file if it exists. If it does not, read another platform's settings
   file as defaults, but do not overwrite the other platform's file.

2. Resolve the team-owned client ID. Use the optional command argument when
   supplied. Otherwise, if local settings contain `client_id`, offer to reuse it;
   do not silently replace it. If none exists or the user declines reuse, prompt
   for the client ID from the team's Spotify Developer application.

3. Remind the user that the exact loopback redirect URI above must already be
   registered, then run the helper. On Antigravity, resolve `PLUGIN_ROOT` to the
   plugin root (two directories above this skill) because no plugin-root variable
   is set.

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$PWD}}"
python3 "${PLUGIN_ROOT}/skills/configure/scripts/oauth-flow.py" \
  --client-id "<team_client_id>"
```

If `python3` is unavailable, try:

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$PWD}}"
uv run "${PLUGIN_ROOT}/skills/configure/scripts/oauth-flow.py" \
  --client-id "<team_client_id>"
```

The helper prints the authorization URL before trying to open a browser. If
automatic browser opening fails, tell the user to copy that URL into a browser
while the loopback listener continues waiting. Do not recreate the PKCE flow in
shell or ask the user to paste a redirect URL: the verifier is ephemeral and
must remain only in the helper's memory.

If neither Python 3 nor `uv` is available, explain that initial PKCE
authorization requires the bundled Python helper. Offer direct-token mode as a
legacy fallback; it has no automatic refresh.

4. Parse the helper's stdout JSON:

```json
{"access_token":"...","refresh_token":"...","expires_in":3600}
```

Keep diagnostics from stderr separate. Never display a full token. Calculate
`token_expires_at` as the current time plus `expires_in`, in UTC ISO 8601 format.

5. Prompt for `auto_execute` (default `false`) and write the active settings
file with the new OAuth values, `auth_flow: "authorization_code_pkce"`, and the
existing ad account ID or an empty value. Restrict the file to the current user.

6. Define the request wrapper, then discover and select the ad account:

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" configure "$@"; }
```

   1. `api GET "businesses"`
   2. For each selected business, `api GET "businesses/<business_id>/ad_accounts"`
   3. Present account names, IDs, and statuses. Select automatically only when
      exactly one account exists across all businesses.
   4. If discovery fails or returns no accounts, ask for the ad account ID.

   Update `ad_account_id` in the active settings file after selection.

7. Verify the selected account:

```bash
api GET "ad_accounts/<ad_account_id>"
```

After a successful migration from an older OAuth setup, tell macOS users that
the legacy `spotify-ads-api-client-secret` Keychain item is unused and may be
removed. Do not delete it automatically because an older installed plugin may
still need it.

### `token <access_token>`

Legacy direct-token mode for an already-issued bearer token.

1. Accept the token argument and warn that it normally expires in about one
   hour and cannot refresh automatically.
2. Prompt for `auto_execute` (default `false`) and write the settings file with
   `auth_flow: "direct_token"`; leave `refresh_token`, `token_expires_at`, and
   `client_id` empty.
3. Use the same businesses → ad accounts discovery flow, or ask for an account
   ID if discovery fails, then update `ad_account_id`.
4. Verify the selected account with the request wrapper.

## Settings File Format

```markdown
---
access_token: "<token>"
refresh_token: "<refresh_token>"
token_expires_at: "<ISO 8601 timestamp>"
client_id: "<team_client_id>"
auth_flow: "authorization_code_pkce"
ad_account_id: "<uuid>"
environment: "production"
auto_execute: false
---

# Spotify Ads API Settings

Local configuration for the spotify-ads-api plugin.
Do not commit this file to version control.
```

For direct-token mode, set `auth_flow: "direct_token"` and leave
`refresh_token`, `token_expires_at`, and `client_id` empty.

## Verification Results

- **200**: Configuration saved and verified successfully.
- **401/403**: Token may be invalid, expired, or unauthorized for the account.
- **404**: The selected ad account ID may be incorrect.
- Other errors: report the status and the response error without exposing tokens.

## Security and Migration

- Settings files are gitignored through `.codex/*.local.md`,
  `.claude/*.local.md`, and `.agents/*.local.md`.
- Access and refresh tokens stay in the active local settings file. The client
  ID is public application metadata required for refresh.
- The PKCE verifier and state are generated cryptographically. The verifier is
  never printed or persisted.
- Never request, read, store, log, or transmit an application secret.
- Never display full access or refresh tokens; show only a short suffix when
  confirmation is necessary.
- An existing OAuth configuration without `auth_flow` may use an unexpired
  access token, but it cannot refresh. Run OAuth configuration once to replace
  it with PKCE-issued tokens.
