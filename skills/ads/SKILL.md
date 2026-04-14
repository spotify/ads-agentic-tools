---
name: ads
description: Manage Spotify Ads API ad sets and ads — list, create, get, or update.
argument-hint: "ad-sets list | ad-sets create | ads list | ads create | ads get <id>"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Ad Sets & Ads Management

Manage ad sets and ads via the Spotify Ads API. Read settings from `.claude/spotify-ads-api.local.md`.

## Setup

1. Read `.claude/spotify-ads-api.local.md` for `access_token`, `ad_account_id`, `auto_execute`.
2. Base URL: `https://api-partner.spotify.com/ads/v3`
3. If settings missing, instruct user to run `/spotify-ads-api:configure` first.
4. Read `.claude-plugin/plugin.json` to get the plugin `version`. Include `-H "X-Spotify-Ads-Sdk: claude-code-plugin/$PLUGIN_VERSION"` on all API requests.

## Parsing Arguments

The argument format is: `<resource> <operation> [id]`
- Resource: `ad-sets` or `ads`
- Operation: `list`, `create`, `get`, `update`
- If no argument, ask which resource and operation.

## Ad Set Operations

### `ad-sets list`
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "X-Spotify-Ads-Sdk: claude-code-plugin/$PLUGIN_VERSION" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets?limit=50&sort_direction=DESC"
```
Format as table: ID | Name | Campaign ID | Status | Format | Budget | Start

### `ad-sets create`
Prompt for required fields:
- **name** (2-200 chars)
- **campaign_id** (uuid — suggest listing campaigns first)
- **start_time** (ISO 8601 datetime)
- **end_time** (ISO 8601 — **required if budget type is LIFETIME**)
- **budget** — ask for dollar amount and type (DAILY/LIFETIME), convert to micro_amount
- **asset_format** (AUDIO, VIDEO, IMAGE)
- **category** (required — valid `ADV_X_Y` code, fetch from `GET /ad_categories` if needed)
- **targets** — ask for targeting preferences:
  - Age range (e.g., 18-34) → `"age_ranges": [{"min": 18, "max": 34}]`
  - **Geo targeting** — see detailed instructions below
  - Genders (optional) → `"genders": ["MALE", "FEMALE", "NON_BINARY"]`
  - Platforms (optional) → `"platforms": ["ANDROID", "DESKTOP", "IOS"]` (**NOT "MOBILE" or "CONNECTED_DEVICE"**)
  - Placements (required) → `"placements": ["MUSIC"]`
- **bid_strategy** — plain string: `MAX_BID`, `COST_PER_RESULT`, or `UNSET`. Default to `MAX_BID`.
- **bid_micro_amount** (required with MAX_BID) — ask for the bid cap in dollars, convert to micro-amount. This is the maximum CPM the user is willing to pay. Example: "$15 bid cap" = `15000000`

Important: Convert dollar amounts to micro-amounts by multiplying by 1,000,000. This applies to both `budget.micro_amount` and `bid_micro_amount`.

#### Geo-Targeting

**Structure:** `geo_targets` is a **flat object** (NOT an array) with a required `country_code` and optional refinement arrays.

**Lookup Geo IDs:** Use the `/targets/geos` endpoint to find geo IDs:

```bash
# Search by location name
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/targets/geos?country_code=US&q=Connecticut&limit=20"

# Search by postal code
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/targets/geos?country_code=US&q=06103&limit=20"
```

Response includes `id`, `type`, `name`, and `parent_geo_name` for each geo.

**Geo Types:**
- `REGION` — States/provinces (e.g., Connecticut, California, Ontario)
- `DMA_REGION` — Designated Market Areas for media targeting (e.g., "Hartford & New Haven, CT")
- `CITY` — Cities and towns
- `POSTAL_CODE` — ZIP codes (format: "US:06103", "CA:M5H")

**Targeting Examples:**

1. **Country-level** (broadest):
```json
"geo_targets": {
  "country_code": "US"
}
```

2. **State/Region-level**:
```json
"geo_targets": {
  "country_code": "US",
  "region_ids": ["4831725"]  // Connecticut
}
```

3. **DMA-level** (media markets):
```json
"geo_targets": {
  "country_code": "US",
  "dma_ids": ["533"]  // Hartford & New Haven, CT
}
```

4. **City-level**:
```json
"geo_targets": {
  "country_code": "US",
  "city_ids": ["4845411", "5284283"]  // West Hartford, Colchester
}
```

5. **Postal code-level** (most granular):
```json
"geo_targets": {
  "country_code": "US",
  "postal_code_ids": ["US:06103", "US:06105"]
}
```

6. **Multi-level** (combine different geo types):
```json
"geo_targets": {
  "country_code": "US",
  "region_ids": ["4831725"],  // Connecticut
  "dma_ids": ["533"],          // Hartford & New Haven DMA
  "city_ids": ["4845411"]      // West Hartford
}
```

**Workflow:**
1. Ask user for geo preference (e.g., "Connecticut", "Hartford DMA", "West Hartford")
2. Call `/targets/geos` with user's query
3. Display results with type, name, and parent location
4. Let user select from results or refine search
5. Build `geo_targets` object with appropriate IDs
6. NEVER fall back to country-only without asking user first

**Pre-flight audience estimate:** Before executing the POST, run an audience estimate to validate targeting:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "ad_account_id": "<AD_ACCOUNT_ID>",
    "start_date": "<start_time>",
    "asset_format": "<AUDIO|VIDEO|IMAGE>",
    "objective": "<campaign_objective>",
    "bid_strategy": "<MAX_BID|COST_PER_RESULT|UNSET>",
    "bid_micro_amount": <bid>,
    "budget": {"micro_amount": <budget>, "type": "<DAILY|LIFETIME>", "currency": "USD"},
    "targets": { <same targets as above> }
  }' \
  "https://api-partner.spotify.com/ads/v3/estimates/audience"
```

**Note:** This endpoint is NOT scoped under `/ad_accounts/{id}/` — it's at the top level: `POST /estimates/audience`. Use the base URL directly followed by `/estimates/audience`.

Display the estimate summary:
```
Audience Estimate:
  Projected unique users: ~142,000
  Estimated daily reach: 8,500 – 12,000
  Estimated daily impressions: 15,000 – 22,000
  Estimated CPM: $12.50 – $18.00
```

If the audience is too small (low projected users or 400 error), warn the user and suggest:
- Broadening the age range
- Adding more platforms
- Switching from VIDEO to AUDIO format (lower thresholds)
- Expanding geo targeting

Ask whether to proceed, adjust targeting, or cancel before creating the ad set.

**Create the ad set:**

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{...}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets"
```

### `ad-sets get <id>`
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets/$AD_SET_ID"
```

### `ad-sets update <id>`
Prompt for fields to update (min 1). Same fields as create, all optional.

## Ad Operations

### `ads list`
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads?limit=50&sort_direction=DESC"
```
Format as table: ID | Name | Ad Set ID | Status | Delivery

### `ads create`
Prompt for required fields:
- **name** (2-200 chars)
- **ad_set_id** (uuid — suggest listing ad sets first)
- **tagline** (2-40 chars, ad headline)
- **advertiser_name** (2-25 chars)
- **assets** — fetch available assets from `GET /assets` and prompt user to select:
  - `asset_id` (required — audio/video/image creative matching ad set format)
  - `logo_asset_id` (required — logo image)
  - `companion_asset_id` (required for AUDIO format — companion image)
- **call_to_action** — uses field `key` (NOT `type`) and `clickthrough_url` (NOT `url`):
  - `key`: SHOP_NOW, LEARN_MORE, LISTEN_NOW, SIGN_UP, WATCH_NOW, BUY_NOW, DOWNLOAD, etc.
  - `clickthrough_url`: landing page URL
- **delivery** (ON/OFF, default ON)

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{...}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads"
```

### `ads get <id>`
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads/$AD_ID"
```

### `ads update <id>`
Updateable fields: `call_to_action`, `delivery`, `status`.

## Execution Behavior

- If `auto_execute` is `true`, execute directly.
- If `auto_execute` is `false`, present the curl command and ask for confirmation.
- Display responses in readable format.
- Always check the `HTTP_STATUS:` line from curl output to determine success or failure before interpreting the response body.
- On error, show the error message from the response body. Never automatically retry POST or PATCH requests — they may have succeeded server-side despite an error response.
- When converting budgets, always confirm the micro-amount with the user (e.g., "$50/day = 50,000,000 micro-amount").
