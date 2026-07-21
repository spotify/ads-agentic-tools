---
name: campaigns
description: List, create, get, or update Spotify Ads API campaigns.
argument-hint: "list | create | get <campaign_id> | update <campaign_id>"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Campaign Management

Manage campaigns via the Spotify Ads API. Read settings from the active platform settings file for credentials and configuration.

## Setup

1. Read `access_token`, `ad_account_id`, and `auto_execute` from the active platform settings file:
   - Codex: prefer `.codex/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.agents/spotify-ads-api.local.md`.
   - Claude: prefer `.claude/spotify-ads-api.local.md`, then fall back to `.codex/spotify-ads-api.local.md`, then `.agents/spotify-ads-api.local.md`.
   - Antigravity: prefer `.agents/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.codex/spotify-ads-api.local.md`.
2. Base URL: `https://api-partner.spotify.com/ads/v3`
3. If no settings file exists, instruct the user to run the configure skill first (`/spotify-ads-api:configure` on Claude/Codex, `/configure` on Antigravity).
4. Read the active platform manifest for the plugin `version`: `.codex-plugin/plugin.json` on Codex, `.claude-plugin/plugin.json` on Claude, or `plugin.json` (plugin root) on Antigravity.
5. Set `SDK_PRODUCT` to `codex-plugin` on Codex, `claude-code-plugin` on Claude, or `antigravity-cli-plugin` on Antigravity. Set `SDK_HEADER="X-Spotify-Ads-Sdk: $SDK_PRODUCT/$PLUGIN_VERSION"` and `SKILL_HEADER="X-Spotify-Ads-Skill: campaigns"`. Include `-H "$SDK_HEADER"` and `-H "$SKILL_HEADER"` on all API requests.

## Operations

Parse the user's argument to determine the operation:

### `list` (default if no argument)
List campaigns for the configured ad account.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns?limit=50&sort_direction=DESC"
```

Format the output as a table: ID | Name | Status | Objective | Created

### `create`
Prompt the user for required fields:
- **name** (string, 2-200 chars)
- **objective** (REACH, CLICKS, VIDEO_VIEWS, CONVERSIONS, LEAD_GEN, EVEN_IMPRESSION_DELIVERY, PODCAST_STREAMS, APP_INSTALLS, WEBSITE_VISITS)

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"name":"...","objective":"..."}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns"
```

### `get <campaign_id>`
Fetch a specific campaign by ID.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns/$CAMPAIGN_ID"
```

Display all campaign fields in a readable format.

### `update <campaign_id>`
Prompt the user for fields to update (at least 1 required):
- **name** (string, optional)
- **status** (ACTIVE, PAUSED, ARCHIVED, optional)

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"name":"...","status":"..."}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns/$CAMPAIGN_ID"
```

## Execution Behavior

- If `auto_execute` is `true`, execute the curl command directly.
- If `auto_execute` is `false`, present the curl command to the user and ask for confirmation before executing.
- Always display the API response in a readable format.
- Always check the `HTTP_STATUS:` line from curl output to determine success or failure before interpreting the response body.
- On error (non-2xx response), show the error message from the response body. Never automatically retry POST or PATCH requests — they may have succeeded server-side despite an error response.
