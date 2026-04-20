---
name: campaigns
description: List, create, get, or update Spotify Ads API campaigns.
argument-hint: "list | create | get <campaign_id> | update <campaign_id>"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Campaign Management

Manage campaigns via the Spotify Ads API. Read settings from `.claude/spotify-ads-api.local.md` for credentials and configuration.

## Setup

1. Read `.claude/spotify-ads-api.local.md` to get `access_token`, `ad_account_id`, and `auto_execute`.
2. Base URL: `https://api-partner.spotify.com/ads/v3`
3. If settings file is missing, instruct the user to run `/spotify-ads-api:configure` first.
4. Read `.claude-plugin/plugin.json` to get the plugin `version`. Set `SDK_HEADER="X-Spotify-Ads-Sdk: claude-code-plugin/$PLUGIN_VERSION"` and include `-H "$SDK_HEADER"` on all API requests.

## Operations

Parse the user's argument to determine the operation:

### `list` (default if no argument)
List campaigns for the configured ad account.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns?limit=50&sort_direction=DESC"
```

Format the output as a table: ID | Name | Status | Objective | Created

### `create`
Prompt the user for required fields:
- **name** (string, 2-200 chars)
- **objective** (REACH, CLICKS, VIDEO_VIEWS, CONVERSIONS, LEAD_GEN, EVEN_IMPRESSION_DELIVERY)

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"name":"...","objective":"..."}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns"
```

### `get <campaign_id>`
Fetch a specific campaign by ID.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
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
