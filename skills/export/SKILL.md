---
name: export
description: Export Spotify Ads API campaign data to CSV — full campaign hierarchies with ad sets, ads, targeting, budgets, and performance metrics for offline review, campaign analysis, or budget reconciliation.
argument-hint: "[campaign_id] [--metrics] [--date-range <start> <end>]"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Campaign Data Export

Export campaign hierarchies to CSV for offline review, combining entity data with optional performance metrics.

## Setup

1. Read `access_token`, `ad_account_id`, and `auto_execute` from the active platform settings file:
   - Codex: prefer `.codex/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.agents/spotify-ads-api.local.md`.
   - Claude: prefer `.claude/spotify-ads-api.local.md`, then fall back to `.codex/spotify-ads-api.local.md`, then `.agents/spotify-ads-api.local.md`.
   - Antigravity: prefer `.agents/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.codex/spotify-ads-api.local.md`.
2. Base URL: `https://api-partner.spotify.com/ads/v3`
3. If no settings file exists, instruct the user to run the configure skill first (`/spotify-ads-api:configure` on Claude/Codex, `/configure` on Antigravity).
4. Read the active platform manifest for the plugin `version`: `.codex-plugin/plugin.json` on Codex, `.claude-plugin/plugin.json` on Claude, or `plugin.json` (plugin root) on Antigravity.
5. Set `SDK_PRODUCT` to `codex-plugin` on Codex, `claude-code-plugin` on Claude, or `antigravity-cli-plugin` on Antigravity. Set `SDK_HEADER="X-Spotify-Ads-Sdk: $SDK_PRODUCT/$PLUGIN_VERSION"` and include `-H "$SDK_HEADER"` on all API requests.

## Parsing Arguments

- No argument → Export all campaigns
- `<campaign_id>` (UUID) → Export a specific campaign
- `--metrics` → Include performance metrics (impressions, spend, reach, etc.)
- `--date-range <start> <end>` → Metric date range (ISO 8601). Default: last 30 days.
- If ambiguous, ask the user.

---

## Step 1: Ask Export Preferences

Ask the user to confirm:
- **Scope**: All campaigns or a specific campaign?
- **Include metrics?** Entity data only, or include performance metrics?
- **Output path**: Default `./spotify-ads-export-YYYY-MM-DD.csv`, or user-specified path.

---

## Step 2: Fetch Entity Data

Fetch all entity data with full pagination. Unlike other skills that show the first page, export must retrieve **every** entity to produce a complete file.

### Fetch campaigns

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns?limit=50&offset=0"
```

Check `paging.total_results` in the response. If `total_results > 50`, make additional requests incrementing `offset` by 50 until all campaigns are fetched. For a single-campaign export, use:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns/$CAMPAIGN_ID"
```

### Fetch ad sets

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets?limit=50&offset=0"
```

For a single campaign: add `&campaign_ids=$CAMPAIGN_ID`. Paginate with `offset` until all ad sets are fetched.

### Fetch ads

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads?limit=50&offset=0"
```

For a single campaign: add `&campaign_ids=$CAMPAIGN_ID`. Paginate with `offset` until all ads are fetched.

---

## Step 3: Fetch Metrics (if requested)

When metrics are included, fetch aggregate reports at each entity level. For a single-campaign export, add `entity_ids=$CAMPAIGN_ID&entity_ids_type=CAMPAIGN` to every report request so the export does not rely on the first unfiltered page containing the requested campaign's metrics.

### Campaign-level metrics

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=CAMPAIGN&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&fields=FREQUENCY&fields=CTR&fields=COMPLETES&\
granularity=LIFETIME&\
entity_status_type=CAMPAIGN&\
limit=50"
```

If a date range is specified, switch to `granularity=DAY` and add `&report_start=<start>&report_end=<end>`.
Use UTC midnight timestamps such as `2026-05-01T00:00:00Z`. Do not send `report_start` or `report_end` with `granularity=LIFETIME`.
Paginate with `continuation_token` if present in the response.

### Ad set-level metrics

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=AD_SET&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&fields=FREQUENCY&fields=COMPLETES&fields=COMPLETION_RATE&\
granularity=LIFETIME&\
entity_status_type=AD_SET&\
include_parent_entity=true&\
limit=50"
```

For a single-campaign export, add `&entity_ids=$CAMPAIGN_ID&entity_ids_type=CAMPAIGN`. Paginate with `continuation_token` if present in the response.

### Ad-level metrics

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=AD&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&\
granularity=LIFETIME&\
entity_status_type=AD&\
include_parent_entity=true&\
limit=50"
```

For a single-campaign export, add `&entity_ids=$CAMPAIGN_ID&entity_ids_type=CAMPAIGN`. Paginate with `continuation_token` if present.

---

## Step 4: Build and Write CSV

### CSV columns

The CSV is **denormalized** — one row per ad, with campaign and ad set data repeated on each row. Ad sets with no ads get a row with blank ad columns.

**Entity columns:**
- `campaign_id`, `campaign_name`, `campaign_status`, `campaign_objective`
- `ad_set_id`, `ad_set_name`, `ad_set_status`, `ad_set_format`, `ad_set_budget_type`, `ad_set_budget_amount`, `ad_set_bid_strategy`, `ad_set_bid_amount`, `ad_set_start_time`, `ad_set_end_time`, `ad_set_delivery`
- `ad_set_geo_country`, `ad_set_geo_regions`, `ad_set_age_min`, `ad_set_age_max`, `ad_set_platforms`, `ad_set_placements`, `ad_set_genders`
- `ad_id`, `ad_name`, `ad_status`, `ad_delivery`, `ad_tagline`, `ad_advertiser_name`, `ad_cta_key`, `ad_cta_url`

**Metric columns (when `--metrics` is used):**
- `impressions`, `spend`, `clicks`, `reach`, `frequency`, `ctr`, `completes`, `completion_rate`

### Data transformations

- **Budget/bid amounts**: Divide `micro_amount` by 1,000,000 to display in dollars (e.g., `50000000` → `50.00`).
- **Metric SPEND**: Values from `aggregate_reports` are already in dollars — display directly.
- **Geo targeting**: Flatten to `ad_set_geo_country` = country code string, `ad_set_geo_regions` = comma-separated region/DMA/city names if available (IDs if names are not in the response).
- **Age ranges**: Extract first range's `min` and `max` into `ad_set_age_min` and `ad_set_age_max`.
- **Arrays** (platforms, placements, genders): Join with commas (e.g., `"ANDROID,DESKTOP,IOS"`).
- **CSV quoting**: Wrap values containing commas, quotes, or newlines in double quotes. Escape internal double quotes by doubling them (`""`).

### Join logic

Match entities by ID:
- Each ad belongs to an ad set (via `ad_set_id`) which belongs to a campaign (via `campaign_id`).
- Metrics join on `entity_id` from the report rows to the entity's `id`.
- If an entity has no metrics (zero impressions, new campaign), include the row with blank metric columns.

### Write the file

Write the CSV header and rows with a structured CSV writer. Prefer Python's standard `csv` module, or use `jq @csv` if all rows are already available as JSON. Do not build CSV rows with `echo` or string concatenation; that will corrupt values containing commas, quotes, or newlines.

Example Python shape:

```python
import csv

columns = [
    "campaign_id", "campaign_name", "campaign_status", "campaign_objective",
    "ad_set_id", "ad_set_name", "ad_set_status", "ad_set_format",
    "ad_set_budget_type", "ad_set_budget_amount", "ad_set_start_time",
    "ad_set_end_time", "ad_id", "ad_name", "ad_status", "ad_delivery",
    "impressions", "spend", "clicks", "reach",
]

with open(output_path, "w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(rows)
```

Build `rows` from parsed API JSON before writing. Let the CSV writer handle quoting and escaping.

---

## Step 5: Display Summary

After writing the file, display:

```
Export complete: ./spotify-ads-export-2026-05-14.csv
  Campaigns: 3
  Ad Sets: 7
  Ads: 12
  Metrics included: Yes (lifetime, last 30 days)
  File size: 4.2 KB
```

---

## Execution Behavior

- If `auto_execute` is `true`, execute all API calls directly and write the file.
- If `auto_execute` is `false`, present the curl commands for the first fetch and ask for confirmation before executing. After confirmation, execute all remaining fetches without additional prompts.
- Always check the `HTTP_STATUS:` line from curl output to determine success or failure before interpreting the response body.
- On error from any fetch, show the error and continue with available data. Note which entity types are missing from the export.
- For large accounts (50+ campaigns), note that pagination will require multiple API calls and may take 30-60 seconds.

## Cross-references

- For server-generated async CSV reports with different column structure, use `/spotify-ads-api:report async-create`.
- For a quick visual overview instead of a file export, use `/spotify-ads-api:dashboard`.
- After reviewing exported data, use `/spotify-ads-api:bulk` for batch changes.
