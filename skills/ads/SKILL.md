---
name: ads
description: Manage Spotify Ads API ad sets and ads — list, create, get, or update.
argument-hint: "ad-sets list | ad-sets create | ads list | ads create | ads get <id>"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Ad Sets & Ads Management

Manage ad sets and ads via the Spotify Ads API. Read settings from `.claude/spotify-ads-api.local.md`.

## Setup

1. Read `.claude/spotify-ads-api.local.md` for `access_token`, `ad_account_id`, `environment`, `auto_execute`.
2. Determine base URL from environment.
3. If settings missing, instruct user to run `/spotify-ads-api:configure` first.

## Parsing Arguments

The argument format is: `<resource> <operation> [id]`
- Resource: `ad-sets` or `ads`
- Operation: `list`, `create`, `get`, `update`
- If no argument, ask which resource and operation.

## Ad Set Operations

### `ad-sets list`
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
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
  - Country (e.g., US) → `"geo_targets": {"country_code": "US"}` (**flat object, NOT array**)
  - Genders (optional) → `"genders": ["MALE", "FEMALE", "NON_BINARY"]`
  - Platforms (optional) → `"platforms": ["ANDROID", "DESKTOP", "IOS"]` (**NOT "MOBILE" or "CONNECTED_DEVICE"**)
  - Placements (required) → `"placements": ["MUSIC"]`
- **bid_strategy** — plain string: `MAX_BID`, `COST_PER_RESULT`, or `UNSET`. Default to `MAX_BID`.
- **bid_micro_amount** (required with MAX_BID) — ask for the bid cap in dollars, convert to micro-amount. This is the maximum CPM the user is willing to pay. Example: "$15 bid cap" = `15000000`

Important: Convert dollar amounts to micro-amounts by multiplying by 1,000,000. This applies to both `budget.micro_amount` and `bid_micro_amount`.

```bash
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{...}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets"
```

### `ad-sets get <id>`
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets/$AD_SET_ID"
```

### `ad-sets update <id>`
Prompt for fields to update (min 1). Same fields as create, all optional.

## Ad Operations

### `ads list`
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
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
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{...}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads"
```

### `ads get <id>`
```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads/$AD_ID"
```

### `ads update <id>`
Updateable fields: `call_to_action`, `delivery`, `status`.

## Execution Behavior

- If `auto_execute` is `true`, execute directly.
- If `auto_execute` is `false`, present the curl command and ask for confirmation.
- Display responses in readable format.
- On error, show the error message from the response body.
- When converting budgets, always confirm the micro-amount with the user (e.g., "$50/day = 50,000,000 micro-amount").
