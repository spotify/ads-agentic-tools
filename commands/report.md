---
name: report
description: Pull Spotify Ads API reporting data — aggregate metrics, audience insights, or async CSV reports.
argument-hint: "aggregate | insights | async-create | async-status <report_id>"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Reporting

Pull reporting data from the Spotify Ads API. Read settings from `.claude/spotify-ads-api.local.md`.

## Setup

1. Read `.claude/spotify-ads-api.local.md` for credentials and config.
2. Determine base URL from environment.
3. If settings missing, instruct user to run `/spotify-ads-api:configure` first.

## Operations

### `aggregate` (default if no argument)
Get aggregated campaign metrics.

Prompt for:
- **entity_type** — What to report on (campaign, ad_set, ad)
- **report_fields** — Metrics to include (suggest: IMPRESSIONS, SPEND, CLICKS, REACH, CTR, CPM)
- **report_start** (ISO 8601)
- **report_end** (ISO 8601)
- **granularity** (HOUR, DAY, LIFETIME — default DAY)
- **entity_ids** (optional — specific campaign/ad set/ad IDs)

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=CAMPAIGN&\
report_fields=IMPRESSIONS,SPEND,CLICKS,REACH&\
report_start=2025-01-01T00:00:00Z&\
report_end=2025-01-31T23:59:59Z&\
granularity=DAY&\
limit=50"
```

Format the response as a readable table with stats broken out per entity and time period.

### `insights`
Get audience insight breakdowns.

Prompt for:
- **insight_dimension** (GENDER, PLATFORM, LOCATION, ARTIST, GENRE)
- **report_fields** — Metrics to include
- **entity_ids** — Campaign or ad set IDs to analyze

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/insight_reports?\
insight_dimension=GENDER&\
report_fields=IMPRESSIONS,SPEND,CLICKS&\
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
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
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
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/async_reports/$REPORT_ID"
```

If complete, display the download URL. If still processing, report the status and suggest checking again later.

## Execution Behavior

- If `auto_execute` is `true`, execute directly.
- If `auto_execute` is `false`, present the curl command and ask for confirmation.
- Always format report data in readable tables when possible.
- For large result sets, summarize key metrics and offer to show full data.
