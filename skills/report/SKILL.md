---
name: report
description: Pull Spotify Ads API reporting data — aggregate metrics, audience insights, or async CSV reports.
argument-hint: "aggregate | insights | async-create | async-status <report_id>"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Reporting

Pull reporting data from the Spotify Ads API. Read settings from `.claude/spotify-ads-api.local.md`.

## Setup

1. Read `.claude/spotify-ads-api.local.md` for `access_token`, `ad_account_id`, `auto_execute`.
2. Base URL: `https://api-partner.spotify.com/ads/v3`
3. If settings missing, instruct user to run `/spotify-ads-api:configure` first.
4. Read `.claude-plugin/plugin.json` to get the plugin `version`. Include `-H "X-Spotify-Ads-Sdk: claude-code-plugin/$PLUGIN_VERSION"` on all API requests.

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
- **report_start** / **report_end** (ISO 8601, optional for LIFETIME)
- **entity_ids** + **entity_ids_type** (optional — filter to specific IDs)
- **include_parent_entity** (optional, boolean — include parent info for AD_SET/AD)

**Important:** Array query parameters must use **repeated parameter names**, NOT comma-separated.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "X-Spotify-Ads-Sdk: claude-code-plugin/$PLUGIN_VERSION" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=CAMPAIGN&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&fields=FREQUENCY&\
granularity=LIFETIME&\
limit=50"
```

**Granularity constraints:**
- `LIFETIME` / `DAY`: date range must be within 90 days
- `HOUR`: date range must be within the last 2 weeks

Format the response as a readable table with stats broken out per entity. Filter out rows with zero impressions for cleaner output.

### `insights`
Get audience insight breakdowns.

Prompt for:
- **insight_dimension** (GENDER, PLATFORM, LOCATION, ARTIST, GENRE)
- **fields** — Metrics to include (same `fields` param as aggregate, repeated format)
- **entity_ids** — Campaign or ad set IDs to analyze

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/insight_reports?\
insight_dimension=GENDER&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&\
entity_ids=$ENTITY_IDS"
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

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "...",
    "granularity": "DAY",
    "dimensions": ["CAMPAIGN_NAME", "AD_SET_NAME"],
    "metrics": ["IMPRESSIONS_ON_SPOTIFY", "SPEND", "CLICKS"],
    "report_start": "2025-01-01T00:00:00Z",
    "report_end": "2025-01-31T23:59:59Z"
  }' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/async_reports"
```

After creating, show the report ID and suggest checking status with `async-status`.

### `async-status <report_id>`
Check the status of an async report and get the download URL when ready.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/async_reports/$REPORT_ID"
```

If complete, display the download URL. If still processing, report the status and suggest checking again later.

## Execution Behavior

- If `auto_execute` is `true`, execute directly.
- If `auto_execute` is `false`, present the curl command and ask for confirmation.
- Always format report data in readable tables when possible.
- For large result sets, summarize key metrics and offer to show full data.
