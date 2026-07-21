---
name: campaigns
description: List, create, get, or update Spotify Ads API campaigns.
argument-hint: "list | create | get <campaign_id> | update <campaign_id>"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Campaign Management

Manage campaigns via the Spotify Ads API. Read settings from the active platform settings file for credentials and configuration.

## Setup

Set the plugin root and define the request wrapper:

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" campaigns "$@"; }
```

To retrieve settings values (TOKEN, AD_ACCOUNT_ID, AUTO_EXECUTE, BASE_URL) for use outside API calls, run `api --env`.

## Operations

Parse the user's argument to determine the operation:

### `list` (default if no argument)
List campaigns for the configured ad account.

```bash
api GET "ad_accounts/{ad_account_id}/campaigns?limit=50&sort_direction=DESC"
```

Format the output as a table: ID | Name | Status | Objective | Created

### `create`
Prompt the user for required fields:
- **name** (string, 2-200 chars)
- **objective** (REACH, CLICKS, VIDEO_VIEWS, CONVERSIONS, LEAD_GEN, EVEN_IMPRESSION_DELIVERY, PODCAST_STREAMS, APP_INSTALLS, WEBSITE_VISITS)

```bash
api POST "ad_accounts/{ad_account_id}/campaigns" \
  '{"name":"...","objective":"..."}'
```

### `get <campaign_id>`
Fetch a specific campaign by ID.

```bash
api GET "ad_accounts/{ad_account_id}/campaigns/$CAMPAIGN_ID"
```

Display all campaign fields in a readable format.

### `update <campaign_id>`
Prompt the user for fields to update (at least 1 required):
- **name** (string, optional)
- **status** (ACTIVE, PAUSED, ARCHIVED, optional)

```bash
api PATCH "ad_accounts/{ad_account_id}/campaigns/$CAMPAIGN_ID" \
  '{"name":"...","status":"..."}'
```

## Execution Behavior

- If `auto_execute` is `true`, execute the curl command directly.
- If `auto_execute` is `false`, present the curl command to the user and ask for confirmation before executing.
- Always display the API response in a readable format.
- Always check the `HTTP_STATUS:` line from curl output to determine success or failure before interpreting the response body.
- On error (non-2xx response), show the error message from the response body. Never automatically retry POST or PATCH requests — they may have succeeded server-side despite an error response.
