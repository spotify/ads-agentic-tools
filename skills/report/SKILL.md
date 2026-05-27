---
name: report
description: Pull Spotify Ads API reporting data — aggregate metrics, audience insights, or async CSV reports.
argument-hint: "aggregate | insights | async-create | async-status <report_id>"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Reporting

Pull reporting data from the Spotify Ads API. Read settings from the active platform settings file.

## Setup

1. Read `access_token`, `ad_account_id`, and `auto_execute` from the active platform settings file:
   - Codex: prefer `.codex/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`.
   - Claude: prefer `.claude/spotify-ads-api.local.md`, then fall back to `.codex/spotify-ads-api.local.md`.
2. Base URL: `https://api-partner.spotify.com/ads/v3`
3. If neither settings file exists, instruct the user to run `/spotify-ads-api:configure` first.
4. Read the active platform manifest for the plugin `version`: `.codex-plugin/plugin.json` on Codex or `.claude-plugin/plugin.json` on Claude.
5. Set `SDK_PRODUCT` to `codex-plugin` on Codex or `claude-code-plugin` on Claude. Set `SDK_HEADER="X-Spotify-Ads-Sdk: $SDK_PRODUCT/$PLUGIN_VERSION"` and include `-H "$SDK_HEADER"` on all API requests.

## Operations

### `aggregate` (default if no argument)
Get aggregated campaign metrics.

Prompt for:
- **entity_type** — What to report on: `CAMPAIGN`, `AD_SET`, `AD`, or `AD_ACCOUNT`
- **fields** — Metrics to include. **Parameter name is `fields`, NOT `report_fields`.**
  Suggested: `IMPRESSIONS`, `SPEND`, `CLICKS`, `REACH`, `FREQUENCY`, `COMPLETES`
  Full list: IMPRESSIONS, SPEND, CLICKS, REACH, FREQUENCY, LISTENERS, NEW_LISTENERS,
  STREAMS, COMPLETES, COMPLETION_RATE, STARTS, FIRST_QUARTILES, MIDPOINTS, THIRD_QUARTILES,
  VIDEO_VIEWS, CTR, OFF_SPOTIFY_IMPRESSIONS
- **granularity** (HOUR, DAY, LIFETIME — default LIFETIME)
- **report_start** / **report_end** (ISO 8601; required for DAY/HOUR, do not send for LIFETIME)
- **entity_ids** + **entity_ids_type** (optional — filter to specific IDs)
- **include_parent_entity** (optional, boolean — include parent info for AD_SET/AD)

**Important:** Array query parameters must use **repeated parameter names**, NOT comma-separated.
**Validation guardrails:**
- `limit` must be 1-50.
- `entity_type` must be exactly `CAMPAIGN`, `AD_SET`, `AD`, or `AD_ACCOUNT`.
- If `entity_ids` is present, always include `entity_ids_type`.
- If `statuses` is present, always include `entity_status_type`; it must match the status owner.
- Do not use `segments`, `dimensions`, `groupBy`, or async-report `metrics` names on aggregate reports.
- Do not include `report_start` or `report_end` when `granularity=LIFETIME`; use `DAY` for date-ranged reporting.
- For `DAY`, use UTC midnight timestamps for both start and end, e.g. `2026-05-01T00:00:00Z`.
- Do not guess conversion metric names. Valid aggregate conversion-style fields include `PAGE_VIEWS`, `LEADS`, `ADD_TO_CART`, `PURCHASES`, `REVENUE`, `RETURN_ON_AD_SPEND`, `AVERAGE_ORDER_VALUE`, `START_CHECKOUT`, and `SIGN_UPS`.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=CAMPAIGN&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&fields=FREQUENCY&\
granularity=LIFETIME&\
limit=50"
```

**Granularity constraints:**
- `LIFETIME`: do not send `report_start` or `report_end`
- `DAY`: date range must be within 90 days and both timestamps must be UTC midnight
- `HOUR`: date range must be within the last 2 weeks

Format the response as a readable table with stats broken out per entity. Filter out rows with zero impressions for cleaner output.

### `insights`
Get audience insight breakdowns.

Prompt for:
- **insight_dimension** — `ACT_AND_SET`, `AGE`, `AUDIENCE`, `CITY`, `COUNTRY`, `FORMAT`,
  `GENDER`, `GENRE`, `INTERESTS`, `METRO`, `PLACEMENT`, `PLATFORM`,
  `PODCAST_EPISODE_TOPIC`, `REGION`, or `TONE`
- **fields** — Metrics to include. Use repeated `fields` params. Insight reports do not allow
  `E_CPCL`, `FREQUENCY`, `OFF_SPOTIFY_IMPRESSIONS`, `PAID_LISTENS_FREQUENCY`,
  `SKIPS`, `SPEND`, `STARTS`, or `UNMUTES`.
- **entity_ids** — One ad set ID to analyze
- **entity_ids_type** — Required when `entity_ids` is set; use `AD_SET` for insight reports
- **statuses** + **entity_status_type** (optional; use `AD_SET` for insight reports)

**Insight report guardrails:**
- Insight reports support one `entity_ids` value at a time, and it must be an ad set ID.
- Always send `entity_ids_type=AD_SET` when `entity_ids` is present. Do not use `CAMPAIGN`.
- Do not send `entity_type` on insight reports; `entity_type=AD_SET` does not substitute for `entity_ids_type=AD_SET`.
- Do not send `report_start`, `report_end`, `granularity`, or `limit`; insight reports are LIFETIME only.
- Use only the listed `insight_dimension` values. Do not use `LOCATION`, `GEO`, `DMA`, `STATE`, `ZIP`, `POSTAL`, `POSTAL_CODE`, `MARKET`, `DEVICE`, `OS`, `ARTIST`, `AGE_RANGE`, or `CITY_NAME`.
- For geo breakdowns, map user language to valid dimensions: country -> `COUNTRY`, region/state -> `REGION`, metro/DMA -> `METRO`, city -> `CITY`.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/insight_reports?\
insight_dimension=GENDER&\
fields=IMPRESSIONS&fields=CLICKS&fields=CTR&\
entity_ids=$ENTITY_IDS&\
entity_ids_type=AD_SET"
```

Format results showing the breakdown by the selected dimension.

### `async-create`
Create an async CSV report for download.

Prompt for:
- **name** (2-120 chars, only alphanumeric, underscore, hyphen)
- **granularity** (DAY or LIFETIME)
- **dimensions** — What to group by:
  - AD_ACCOUNT_NAME, CAMPAIGN_NAME, CAMPAIGN_STATUS, CAMPAIGN_OBJECTIVE
  - AD_SET_NAME, AD_SET_STATUS, AD_SET_BUDGET, AD_SET_COST_MODEL
  - AD_NAME
- **metrics** — What to measure:
  - IMPRESSIONS_ON_SPOTIFY, IMPRESSIONS_OFF_SPOTIFY, SPEND, CLICKS
  - REACH, FREQUENCY, LISTENERS, NEW_LISTENERS, STREAMS
  - AD_COMPLETES, CTR, CPM, COMPLETION_RATE
- **report_start** (required if granularity=DAY)
- **report_end** (optional)
- **campaign_ids** (optional — filter to specific campaigns)
- **statuses** (optional, default: [ACTIVE])

**Async report guardrails:**
- Async report `dimensions` are entity metadata columns only. Do not use `CITY`, `COUNTRY`, `REGION`, `DMA`, `POSTAL_CODE`, `LOCATION`, `AGE`, `GENDER`, `PLATFORM`, `DEVICE`, or `OS` here; use `insight_reports` for those breakdowns.
- Use request fields `dimensions` and `metrics`, not `groupBy`, `fields`, `dateRange`, or `entityType`.
- If `granularity=DAY`, include `report_start`; use UTC midnight timestamps for date boundaries.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "...",
    "granularity": "DAY",
    "dimensions": ["CAMPAIGN_NAME", "AD_SET_NAME"],
    "metrics": ["IMPRESSIONS_ON_SPOTIFY", "SPEND", "CLICKS"],
    "report_start": "2025-01-01T00:00:00Z",
    "report_end": "2025-01-31T00:00:00Z"
  }' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/async_reports"
```

After creating, show the report ID and suggest checking status with `async-status`.

### `async-status <report_id>`
Check the status of an async report and get the download URL when ready.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/async_reports/$REPORT_ID"
```

If complete, display the download URL. If still processing, report the status and suggest checking again later.

## Execution Behavior

- If `auto_execute` is `true`, execute directly.
- If `auto_execute` is `false`, present the curl command and ask for confirmation.
- Always format report data in readable tables when possible.
- For large result sets, summarize key metrics and offer to show full data.
