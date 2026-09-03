# Spotify Ads API Plugin

Manage Spotify ad campaigns with natural language. Capabilities are packaged as Agent Skills (campaigns, ads, assets, reporting, dashboards, monitoring, bulk operations, cloning, exports, and a full campaign builder). Describe what you want — e.g. "show my campaign dashboard" or "create a campaign for my podcast" — or run `/skills list` to see everything available.

## Settings

Read and write per-user configuration in `.agents/spotify-ads-api.local.md` (YAML frontmatter: `access_token`, `refresh_token`, `token_expires_at`, `client_id`, `ad_account_id`, `environment`, `auto_execute`). If that file does not exist, fall back to `.claude/spotify-ads-api.local.md`, then `.codex/spotify-ads-api.local.md`.

Never commit these files. The `client_secret` is stored in the macOS Keychain (service: `spotify-ads-api-client-secret`, account: `spotify-ads-api`), not in the settings file.

## First-Time Setup

Run `/configure` (or ask to "configure Spotify Ads API credentials") to set up OAuth 2.0 authentication and select an ad account. Documentation elsewhere may reference `/spotify-ads-api:configure` — that is the Claude Code/Codex name for the same configure skill.

## Tracking Headers

Every Spotify Ads API request must carry both tracking headers, so usage and error rates can be attributed to the skill that made the call:

- `X-Spotify-Ads-Sdk: antigravity-cli-plugin/<version>`
- `X-Spotify-Ads-Skill: <skill-name>`

The shared request wrapper sets both for you, and is the preferred way to call the API:

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" <skill-name> "$@"; }
api GET "ad_accounts/{ad_account_id}/campaigns?limit=50"
```

When a call genuinely cannot use the wrapper, such as a multipart upload, pull the values into the shell first and pass them explicitly:

```bash
eval $(api --env)   # sets TOKEN, AD_ACCOUNT_ID, BASE_URL, SDK_HEADER, SKILL_HEADER
curl -s -H "Authorization: Bearer $TOKEN" -H "$SDK_HEADER" -H "$SKILL_HEADER" ...
```

Do not hand-write curl to `api-partner.spotify.com` without both headers. Antigravity's PreToolUse contract cannot rewrite a command, so unlike Claude Code and Codex the hook cannot add missing headers for you. It will only warn, and the request stays unattributable.

## Token Expiry

A PreToolUse hook refreshes expired OAuth tokens automatically before API calls, and warns when a call is missing its skill attribution header. Both Antigravity CLI (`agy plugin install`) and Antigravity 2.0 auto-discover `hooks.json` at the plugin root.

If a request still returns 401, refresh the token per the configure skill's instructions or re-run `/configure`.

## Contributors

If you are editing this repository itself (not using the plugin), `AGENTS.md` is the canonical instruction file — read it before making changes.
