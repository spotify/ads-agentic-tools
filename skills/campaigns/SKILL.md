---
name: campaigns
description: List or get Spotify Ads API campaigns, and stage campaign creation or updates through drafts by default. Use direct live writes only when explicitly requested.
argument-hint: "list | create | get <campaign_id> | update <campaign_id> | create-live | update-live <campaign_id>"
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

Before the first Ads API v3 call, read and follow `$PLUGIN_ROOT/skills/api-reference/references/live-openapi.md`.

To retrieve settings values (TOKEN, AD_ACCOUNT_ID, AUTO_EXECUTE, BASE_URL, SDK_HEADER, SKILL_HEADER, PLUGIN_VERSION) for use outside API calls, run `api --env`. The output is eval-safe, so `eval $(api --env)` assigns them all.

## Operations

Parse the user's argument to determine the operation:

### `list` (default if no argument)
List campaigns for the configured ad account.

```bash
api GET "ad_accounts/{ad_account_id}/campaigns?limit=50&sort_direction=DESC"
```

Format the output as a table: ID | Name | Status | Objective / Delivery Goal Group | Created

### `create`
Prompt the user for a name and campaign goal. Map the goal to `delivery_goal_group` using the mapping in the drafts skill.
- **name** (string, 2-200 chars)
- **delivery_goal_group** (`AWARENESS`, `WEBSITE_TRAFFIC`, `APP_PROMOTION`, `ENGAGEMENT_ON_SPOTIFY`, or `LEAD_GEN`)

Then read and follow
`$PLUGIN_ROOT/skills/api-reference/references/ad-product-validation.md`. Fetch the live
catalog once for this operation. Validate the final campaign body against `campaign.create`
plus `campaign.both`. An omitted, `UNSET`, or `UNKNOWN` `ad_product` resolves to
`AUCTION`. Do not add a separate validation confirmation.

```bash
api POST "ad_accounts/{ad_account_id}/drafts/campaigns" \
  '{"name":"...","delivery_goal_group":"..."}'
```

Campaign creation is staged by default. Display the returned draft ID and current `draft_hierarchy_version`. Do not publish unless the user separately requests publishing through the drafts skill.

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

Before the PATCH, read and follow
`$PLUGIN_ROOT/skills/api-reference/references/ad-product-validation.md`. Fetch the live
catalog and current campaign once for this operation, deep-merge the proposed changes,
and validate the effective campaign against `campaign.update` plus `campaign.both`.
This applies to status-only updates too. Do not add a separate validation confirmation.

```bash
api GET "ad_accounts/{ad_account_id}/campaigns/$CAMPAIGN_ID"
api GET "ad_accounts/{ad_account_id}/drafts/campaigns/$CAMPAIGN_ID"
```

If the draft GET returns 404, create a draft from the published campaign:

```bash
api POST "ad_accounts/{ad_account_id}/campaigns/$CAMPAIGN_ID/drafts"
```

If a draft already exists, display its current pending fields before combining the requested change. Then update the draft, not the published campaign:

```bash
api PATCH "ad_accounts/{ad_account_id}/drafts/campaigns/$CAMPAIGN_ID" \
  '{"name":"...","status":"..."}'
```

Fetch the draft campaign again for the current version, validate it, and report the result as staged:

```bash
api GET "ad_accounts/{ad_account_id}/drafts/campaigns/$CAMPAIGN_ID"
api POST "ad_accounts/{ad_account_id}/drafts/campaigns/$CAMPAIGN_ID" \
  '{"action":"VALIDATE","draft_hierarchy_version":<version>}'
```

Do not publish unless the user separately asks to publish and confirms immediately before the `PUBLISH` request.

### `create-live` and `update-live <campaign_id>`

Use the published `POST /campaigns` or `PATCH /campaigns/{id}` endpoint only when the user explicitly asks to skip drafts or make an immediate/direct change to the published entity. Explain that direct writes may not be available for every account or credential.

If a direct write returns HTTP 403 or an edit-permission error, do not retry it and do not conclude that the credentials are entirely read-only. State that direct editing of the published campaign was denied and offer the draft workflow instead.

## Execution Behavior

- If `auto_execute` is `true`, execute the curl command directly.
- If `auto_execute` is `false`, present the curl command to the user and ask for confirmation before executing.
- Always display the API response in a readable format.
- Always check the `HTTP_STATUS:` line from curl output to determine success or failure before interpreting the response body.
- On error (non-2xx response), show the error message from the response body. Never automatically retry POST or PATCH requests — they may have succeeded server-side despite an error response.
- Treat a 404 from the draft existence check as "no draft exists"; it is the only signal to call the create-from-published endpoint. Other errors must be shown and the workflow stopped.
