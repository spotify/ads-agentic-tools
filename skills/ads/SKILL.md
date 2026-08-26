---
name: ads
description: List or get Spotify Ads API ad sets and ads, and stage their creation or updates through drafts by default. Use direct live writes only when explicitly requested.
argument-hint: "ad-sets list|create|get|update | ads list|create|get|update | *-live for explicit direct writes"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Ad Sets & Ads Management

Manage ad sets and ads via the Spotify Ads API. Read settings from the active platform settings file.

## Setup

Set the plugin root and define the request wrapper:

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" ads "$@"; }
```

Before the first Ads API v3 call, read and follow `$PLUGIN_ROOT/skills/api-reference/references/live-openapi.md`.

To retrieve settings values (TOKEN, AD_ACCOUNT_ID, AUTO_EXECUTE, BASE_URL) for use outside API calls, run `api --env`.

## Parsing Arguments

The argument format is: `<resource> <operation> [id]`
- Resource: `ad-sets` or `ads`
- Operation: `list`, `create`, `get`, `update`
- If no argument, ask which resource and operation.

For `create` and `update`, default to draft endpoints even when the user does not mention drafts. `create-live` and `update-live` are explicit escape hatches for direct published writes.

## Ad Set Operations

### `ad-sets list`
```bash
api GET "ad_accounts/{ad_account_id}/ad_sets?limit=50&sort_direction=DESC"
```
Format as table: ID | Name | Campaign ID | Status | Format | Budget | Start

### `ad-sets create`
Collect the required fields below first. Before the POST, read and follow
`$PLUGIN_ROOT/skills/api-reference/references/ad-product-validation.md`. Fetch the live
catalog, parent campaign, and any runtime inputs required by its rules, then validate
the final ad set body against `ad_set.create` plus `ad_set.both`. Do not add a separate
validation confirmation.

Prompt for required fields:
- **name** (2-200 chars)
- **campaign_id** (uuid — suggest listing campaigns first)
- **start_time** (ISO 8601 datetime)
- **end_time** (ISO 8601 — **required if budget type is LIFETIME**)
- **budget** — ask for amount in the ad account's billing currency and type (DAILY/LIFETIME), convert to micro_amount
- **asset_format** (AUDIO, VIDEO, IMAGE, CATALOG)
- **category** (required — valid `ADV_X_Y` code, fetch from `GET /ad_categories` if needed)
- **targets** — ask for targeting preferences:
  - Age range (e.g., 18-34) → `"age_ranges": [{"min": 18, "max": 34}]`
  - **Geo targeting** — see detailed instructions below
  - Genders (optional) → `"genders": ["MALE", "FEMALE", "NON_BINARY"]`
  - Platforms (optional) → `"platforms": ["ANDROID", "DESKTOP", "IOS"]` (**NOT "MOBILE" or "CONNECTED_DEVICE"**)
  - Placements (required) → `"placements": ["MUSIC"]`
- **bid_strategy** — plain string: `MAX_BID`, `COST_PER_RESULT`, `AUTOBID`, or `UNSET`. Default to `MAX_BID`.
- **bid_micro_amount** (required with MAX_BID or COST_PER_RESULT, not required with AUTOBID) — ask for the bid cap in the ad account's billing currency, convert to micro-amount. This is the maximum CPM. Example: $15 USD = `15000000`, ¥160 JPY = `160000000`

Important: Convert amounts to micro-amounts by multiplying by 1,000,000. This applies to both `budget.micro_amount` and `bid_micro_amount`.

**Ad set validation guardrails before any POST:**
- Never send zero or negative `budget.micro_amount`; ask for a positive budget and convert it to micro-units.
- Never send `bid_micro_amount: 0` with `MAX_BID` or `COST_PER_RESULT`; ask for a positive bid cap.
- Do not send `bid_micro_amount` with `bid_strategy=UNSET` unless the API response or user-provided source explicitly requires it.
- Keep `budget` to `micro_amount` and `type`; do not include `currency` on ad set create payloads.
- Valid `targets.platforms` values are only `ANDROID`, `DESKTOP`, and `IOS`; never send `WEB`, `MOBILE`, `CONNECTED_DEVICE`, or `ad_platforms`.
- Do not send `cost_model`, `skippable`, `is_skippable`, or `ad_platforms` in ad set create payloads.
- Use age ranges with `min >= 18` unless the user has explicitly confirmed a market/category that allows minors.
- If using `city_ids`, `postal_code_ids`, or `region_ids`, include the parent `country_code` in the same `geo_targets` object.

#### Geo-Targeting

**Structure:** `geo_targets` is a **flat object** (NOT an array) with a required `country_code` and optional refinement arrays.

**Lookup Geo IDs:** Use the `/targets/geos` endpoint to find geo IDs:

```bash
# Search by location name
api GET "targets/geos?country_code=US&q=Connecticut&limit=20"

# Search by postal code
api GET "targets/geos?country_code=US&q=06103&limit=20"
```

Response includes `id`, `type`, `name`, and `parent_geo_name` for each geo.

**Geo Types:**
- `REGION` — States/provinces (e.g., Connecticut, California, Ontario)
- `DMA_REGION` — Designated Market Areas for media targeting (e.g., "Hartford & New Haven, CT"). **Note:** DMA-level targeting via `dma_ids` is no longer supported. DMAs can still be looked up but cannot be used as targeting refinements.
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

3. **City-level**:
```json
"geo_targets": {
  "country_code": "US",
  "city_ids": ["4845411", "5284283"]  // West Hartford, Colchester
}
```

4. **Postal code-level** (most granular):
```json
"geo_targets": {
  "country_code": "US",
  "postal_code_ids": ["US:06103", "US:06105"]
}
```

5. **Multi-level** (combine different geo types):
```json
"geo_targets": {
  "country_code": "US",
  "region_ids": ["4831725"],  // Connecticut
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
api POST "estimates/audience" \
  '{
    "ad_account_id": "<AD_ACCOUNT_ID>",
    "start_date": "<start_time>",
    "asset_format": "<AUDIO|VIDEO|IMAGE|CATALOG>",
    "objective": "<campaign_objective>",
    "bid_strategy": "<MAX_BID|COST_PER_RESULT|AUTOBID|UNSET>",
    "bid_micro_amount": <bid>,
    "budget": {"micro_amount": <budget>, "type": "<DAILY|LIFETIME>", "currency": "USD"},
    "targets": { <same targets as above> }
  }'
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

**Create the draft ad set:**

The `campaign_id` must reference a draft campaign. If the supplied campaign is published, first check for and reuse its draft or create one with `POST /campaigns/{campaign_id}/drafts`.

```bash
api POST "ad_accounts/{ad_account_id}/drafts/ad_sets" \
  '{...}'
```

### `ad-sets get <id>`
```bash
api GET "ad_accounts/{ad_account_id}/ad_sets/$AD_SET_ID"
```

### `ad-sets update <id>`

Before the PATCH, read and follow
`$PLUGIN_ROOT/skills/api-reference/references/ad-product-validation.md`. Fetch the live
catalog, current ad set, parent campaign, and runtime state required by applicable
rules. Deep-merge the proposed PATCH into the current ad set and validate the effective
entity against `ad_set.update` plus `ad_set.both`. Do not add a separate validation
confirmation.

Prompt for fields to update (min 1). Same fields as create, all optional.

Read the published ad set, then check `GET /drafts/ad_sets/{id}`. If it returns 404, create a draft with `POST /ad_sets/{id}/drafts`. If a draft already exists, disclose its pending state before combining changes. PATCH `/drafts/ad_sets/{id}`, resolve its draft `campaign_id`, fetch the draft campaign's current hierarchy version, and validate it. Keep the result staged.

## Ad Operations

### `ads list`
```bash
api GET "ad_accounts/{ad_account_id}/ads?limit=50&sort_direction=DESC"
```
Format as table: ID | Name | Ad Set ID | Status | Delivery

### `ads create`
Collect the required fields and asset selections below first. Before the POST, read and
follow `$PLUGIN_ROOT/skills/api-reference/references/ad-product-validation.md`. Fetch
the live catalog, current parent ad set and campaign, and referenced assets, then
validate the final ad body against `ad.create` plus `ad.both`. Do not add a separate
validation confirmation.

Prompt for required fields:
- **name** (2-200 chars)
- **ad_set_id** (uuid — suggest listing ad sets first)
- **tagline** (2-40 chars, ad headline; required for live ads, optional for drafts)
- **advertiser_name** (2-25 chars)
- **assets** — fetch available assets from `GET /assets` and prompt user to select:
  - `asset_id` (required for live ads, optional for drafts — audio/video/image creative matching ad set format)
  - `logo_asset_id` (required — logo image)
  - `companion_asset_id` (required for AUDIO format — companion image)
- **call_to_action** — uses field `key` (NOT `type`) and `clickthrough_url` (NOT `url`):
  - `key`: SHOP_NOW, LEARN_MORE, LISTEN_NOW, SIGN_UP, WATCH_NOW, BUY_NOW, DOWNLOAD, etc.
  - `clickthrough_url`: landing page URL (required for live ads, optional for drafts)
- **delivery** (ON/OFF, default ON)
- **third_party_tracking** (optional) — array of tracking pixels. Each entry needs:
  - `measurement_event`: **required** — `IMPRESSION`, `CLICKED`, `START`, `FIRST_QUARTILE`, `MIDPOINT`, `THIRD_QUARTILE`, `COMPLETE`, or `VIEWABLE_IMPRESSION`. If omitted, defaults to IMPRESSION — always set explicitly, especially for click trackers.
  - `measurement_partner`: `DCM`, `IAS`, `MOAT`, `DOUBLEVERIFY`, or `UNSET`
  - `url`: the tracking pixel URL
  - Example with both impression and click trackers:
    ```json
    "third_party_tracking": [
      {"measurement_event": "IMPRESSION", "measurement_partner": "DCM", "url": "https://ad.doubleclick.net/ddm/trackimp/..."},
      {"measurement_event": "CLICKED", "measurement_partner": "DCM", "url": "https://ad.doubleclick.net/ddm/trackclk/..."}
    ]
    ```

```bash
api POST "ad_accounts/{ad_account_id}/drafts/ads" \
  '{...}'
```

The `ad_set_id` must reference a draft ad set. If the supplied ad set is published, first check for and reuse its draft or create one with `POST /ad_sets/{ad_set_id}/drafts`.

### `ads get <id>`
```bash
api GET "ad_accounts/{ad_account_id}/ads/$AD_ID"
```

### `ads update <id>`
Before the update, read and follow
`$PLUGIN_ROOT/skills/api-reference/references/ad-product-validation.md`. Fetch the live
catalog, current ad, parent ad set and campaign, and any referenced assets. Deep-merge
the proposed changes into the current ad and validate the effective entity against
`ad.update` (when present) plus `ad.both`. Do not add a separate validation
confirmation.

Read the published ad, then check `GET /drafts/ads/{id}`. If it returns 404, create a draft with `POST /ads/{id}/drafts`. If a draft already exists, disclose its pending state before combining changes. PATCH `/drafts/ads/{id}`, fetch its parent draft ad set to resolve the draft campaign, fetch the campaign's current hierarchy version, and validate it. Keep the result staged.

Draft ad updates support `name`, `advertiser_name`, `tagline`, `assets`, `asset_format`, `call_to_action`, `third_party_tracking`, `placements`, `weight`, and `status`. Always preserve third-party tracking entries the user did not explicitly remove or replace, and set `measurement_event` explicitly on every entry.

### Explicit direct writes

Use `ad-sets create-live`, `ad-sets update-live <id>`, `ads create-live`, or `ads update-live <id>` only when the user explicitly requests an immediate/direct change to a published entity or asks to skip drafts.

If a direct write returns HTTP 403 or an edit-permission error, do not retry it and do not conclude that the credentials are entirely read-only. State that direct editing of the published entity was denied and offer draft staging instead.

## Execution Behavior

- If `auto_execute` is `true`, execute directly.
- If `auto_execute` is `false`, present the curl command and ask for confirmation.
- Display responses in readable format.
- Always check the `HTTP_STATUS:` line from curl output to determine success or failure before interpreting the response body.
- On error, show the error message from the response body. Never automatically retry POST or PATCH requests — they may have succeeded server-side despite an error response.
- When converting budgets, always confirm the micro-amount with the user (e.g., "$50/day = 50,000,000 micro-amount").
- Treat a 404 from a draft existence check as "no draft exists"; for any other error, stop and show the response.
- Never publish a draft without a separate user request and explicit confirmation immediately before `PUBLISH`.
