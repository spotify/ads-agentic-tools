---
name: change-history
description: View a timeline of changes made to campaigns, ad sets, creatives, and other entities in an ad account — who changed what, when, and how.
argument-hint: "list | who changed <entity> | what changed today | budget changes last week"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Change History

Retrieve a paginated timeline of changes made to campaigns, ad sets, creatives, and other entities within an ad account. Useful for auditing who changed what, tracking budget modifications, reviewing status changes, and understanding campaign activity over time.

## Setup

Set the plugin root and define the request wrapper:

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" change-history "$@"; }
```

Before the first Ads API v3 call, read and follow `$PLUGIN_ROOT/skills/api-reference/references/live-openapi.md`.

To retrieve settings values (TOKEN, AD_ACCOUNT_ID, AUTO_EXECUTE, BASE_URL) for use outside API calls, run `api --env`.

## Endpoint

```
GET /ad_accounts/{ad_account_id}/change_history
```

Results are constrained to a rolling 180-day retention window.

## Query Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `entity_type` | enum | No | — | `CAMPAIGN`, `AD_SET`, `AD_ACCOUNT`, `BUSINESS`, `CREATIVE` |
| `entity_ids` | array[string] | No | — | Filter by specific entity IDs |
| `entity_name` | string | No | — | Case-insensitive substring match (2-255 chars); requires `entity_type` |
| `change_ids` | array[string] | No | — | Fetch specific change records by ID |
| `actor_ids` | array[string] | No | — | Filter by who made the change |
| `principal_type` | enum | No | — | `USER`, `SERVICE` |
| `change_category` | enum | No | — | `STATUS`, `BUDGET`, `TARGETING`, `CREATIVE`, `SCHEDULING`, `SETTINGS`, `BILLING` |
| `created_gte` | ISO 8601 | No | 30 days ago | Changes on or after this timestamp |
| `created_lte` | ISO 8601 | No | — | Changes on or before this timestamp |
| `limit` | integer | No | 50 | 1-50 |
| `offset` | integer | No | 0 | Pagination offset |
| `sort_direction` | enum | No | `DESC` | `ASC`, `DESC` |
| `sort_field` | enum | No | `TIMESTAMP` | `TIMESTAMP`, `ENTITY_TYPE`, `PRINCIPAL_TYPE` |

## Operations

Interpret the user's natural language request to determine the right query. Build query parameters from their intent.

### `list` (default if no argument)
Show recent changes for the configured ad account.

```bash
api GET "ad_accounts/{ad_account_id}/change_history?limit=20&sort_direction=DESC"
```

Format the output as a table: Timestamp | Entity Type | Entity Name | Operation | Category | Actor

### Filtered queries

Map the user's request to query parameters:

- **"what changed today"** → `created_gte` set to today at 00:00:00 UTC
- **"budget changes last week"** → `change_category=BUDGET` + `created_gte` set to 7 days ago
- **"who changed campaign X"** → `entity_type=CAMPAIGN` + `entity_name=X`
- **"changes by user@example.com"** → `actor_ids` with the user's principal ID
- **"status changes this month"** → `change_category=STATUS` + `created_gte` set to start of month
- **"show me ad set changes"** → `entity_type=AD_SET`
- **"what did the API change"** → `principal_type=SERVICE`

Build the query string from the mapped parameters:

```bash
api GET "ad_accounts/{ad_account_id}/change_history?entity_type=CAMPAIGN&change_category=BUDGET&created_gte=2026-07-01T00:00:00Z&limit=50&sort_direction=DESC"
```

### Pagination

If `total_results` exceeds the page size, offer to fetch the next page:

```bash
api GET "ad_accounts/{ad_account_id}/change_history?offset=50&limit=50&sort_direction=DESC"
```

### Detail view

When the user asks about a specific change, fetch it by ID:

```bash
api GET "ad_accounts/{ad_account_id}/change_history?change_ids=$CHANGE_ID"
```

Display the full change record including before/after values for each changed field.

## Response Format

Each change record contains:

- **change_id** — Unique identifier for the change event
- **timestamp** — When the change was made
- **entity_type** — What was changed (CAMPAIGN, AD_SET, etc.)
- **entity_id** — ID of the changed entity
- **entity_name** — Name of the changed entity
- **operation** — Type of change: `CREATED`, `CHANGED`, `REMOVED`
- **actor** — Who made the change:
  - `name` — Display name
  - `principal_type` — `USER` or `SERVICE`
  - `category` — `ADVERTISER_USER`, `SUPPORT`, `API_INTEGRATION`, `SYSTEM`, `UNKNOWN`
- **changes** — Array of field-level changes:
  - `field_type` — Internal field identifier
  - `display_label` — Human-readable field name
  - `change_category` — Category of the change
  - `before` — Previous value (null for CREATED operations)
  - `after` — New value (null for REMOVED operations)

## Display Guidelines

- Format timestamps in the user's local timezone when possible, otherwise show UTC with a note
- Show before → after values for CHANGED operations, highlighting what specifically changed
- For CREATED operations, show the initial values set
- Group changes by entity when showing a timeline view
- Summarize large result sets: "42 changes found — showing the 20 most recent"
- When the user asks "how many," return a count from `total_results` without listing every record

## Execution Behavior

- If `auto_execute` is `true`, execute the curl command directly.
- If `auto_execute` is `false`, present the curl command to the user and ask for confirmation before executing.
- Always display the API response in a readable format.
- Always check the `HTTP_STATUS:` line from curl output to determine success or failure before interpreting the response body.
- On error (non-2xx response), show the error message from the response body. Never automatically retry requests.
