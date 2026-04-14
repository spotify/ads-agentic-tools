---
name: build-campaign
description: Create a full campaign (campaign + ad sets + ads) from a plain-text description. Parses natural language into structured API calls.
argument-hint: "<plain-text campaign description>"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Full Campaign Builder

Given a plain-text description of an advertising campaign, parse it into structured API
calls and create the full campaign hierarchy: Campaign → Ad Sets → Ads.

## Setup

1. Read `.claude/spotify-ads-api.local.md` for `access_token`, `ad_account_id`, `auto_execute`.
2. Base URL: `https://api-partner.spotify.com/ads/v3`
3. If settings file is missing, instruct the user to run `/spotify-ads-api:configure` first.
4. Read `.claude-plugin/plugin.json` to get the plugin `version`. Include `-H "X-Spotify-Ads-Sdk: claude-code-plugin/$PLUGIN_VERSION"` on all API requests.

## Step 1: Parse the Campaign Description

Extract the following from the user's plain-text input. If a field is missing or ambiguous,
use the defaults noted below. If a required field cannot be inferred, ask the user.

### Campaign-level fields

| Field | Required | Default |
|-------|----------|---------|
| name | yes | — |
| objective | yes | REACH |

Valid objectives: `REACH`, `CLICKS`, `VIDEO_VIEWS`, `CONVERSIONS`, `LEAD_GEN`, `EVEN_IMPRESSION_DELIVERY`

### Ad set-level fields (one or more)

| Field | Required | Default | Notes |
|-------|----------|---------|-------|
| name | yes | — | 2-200 chars |
| start_time | yes | — | ISO 8601 UTC |
| end_time | required if LIFETIME | — | ISO 8601 UTC |
| budget.micro_amount | yes | — | Dollar amount x 1,000,000 |
| budget.type | yes | DAILY | `DAILY` or `LIFETIME` |
| asset_format | yes | AUDIO | `AUDIO`, `VIDEO`, or `IMAGE` |
| category | yes | — | Valid `ADV_X_Y` code (fetch from `GET /ad_categories` if needed) |
| bid_strategy | yes | MAX_BID | Plain string: `MAX_BID`, `COST_PER_RESULT`, or `UNSET` |
| bid_micro_amount | yes with MAX_BID | 15000000 | Bid cap in micro-units |
| pacing | no | PACING_EVEN | `PACING_EVEN` or `PACING_ASAP` |
| delivery | no | ON | `ON` or `OFF` |
| targets.age_ranges | yes | [{"min":18,"max":54}] | Array of `{min, max}` objects |
| targets.geo_targets | yes | {"country_code":"US"} | **Flat object** with `country_code` string |
| targets.platforms | no | ["ANDROID","DESKTOP","IOS"] | Valid: `ANDROID`, `DESKTOP`, `IOS` |
| targets.placements | yes | ["MUSIC"] | `MUSIC` or `PODCAST` |
| targets.genders | no | [] | `MALE`, `FEMALE`, `NON_BINARY` |

### Ad-level fields (one or more per ad set)

| Field | Required | Notes |
|-------|----------|-------|
| name | yes | 2-200 chars |
| tagline | yes | 2-40 chars |
| advertiser_name | yes | 2-25 chars |
| assets.asset_id | yes | UUID — prompt user to select |
| assets.logo_asset_id | yes | UUID — prompt user to select |
| assets.companion_asset_id | yes (audio) | UUID — required for AUDIO format ads |
| call_to_action.key | yes | e.g. `SHOP_NOW`, `LEARN_MORE`, `LISTEN_NOW`, `SIGN_UP` |
| call_to_action.clickthrough_url | yes | Landing page URL |
| delivery | no | `ON` (default) or `OFF` |

## Step 2: Confirm the Parsed Plan

Before making any API calls, present the full parsed plan as a visual tree:

```
Campaign: "My Campaign" (objective: REACH)
├── Ad Set 1: "Ad Set A" (AUDIO, $75/day, US, ages 25-54, Mar 1 start)
│   └── Ad 1: "My Ad" → SHOP_NOW → example.com
└── Ad Set 2: "Ad Set B" (VIDEO, $500 lifetime, US, ages 18-54, Mar 4–Apr 4)
    └── Ad 2: "My Video Ad" → LEARN_MORE → example.com
```

Also show a table with all field values for each entity. Ask the user to confirm or adjust.

If the ad category was not specified, ask the user to select one using AskUserQuestion.
You can fetch valid categories from `GET /ad_categories` to present options.

## Step 2.5: Validate Audience Size

After the user confirms the plan but before executing API calls, run an audience estimate for each ad set's targeting:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "X-Spotify-Ads-Sdk: claude-code-plugin/$PLUGIN_VERSION" \
  -H "Content-Type: application/json" \
  -d '{
    "ad_account_id": "<AD_ACCOUNT_ID>",
    "start_date": "<start_time>",
    "asset_format": "<AUDIO|VIDEO|IMAGE>",
    "objective": "<campaign_objective>",
    "bid_strategy": "<MAX_BID|COST_PER_RESULT|UNSET>",
    "bid_micro_amount": <bid>,
    "budget": {"micro_amount": <budget>, "type": "<DAILY|LIFETIME>", "currency": "USD"},
    "targets": { <same targets object as the ad set> }
  }' \
  "https://api-partner.spotify.com/ads/v3/estimates/audience"
```

**Important:** This endpoint is NOT scoped under `/ad_accounts/{id}/` — it's at the top level: `POST /estimates/audience`. Use the base URL directly followed by `/estimates/audience`.

Display the estimate results in a summary:

```
Audience Estimate for "Ad Set A":
  Projected unique users: ~142,000
  Estimated daily reach: 8,500 – 12,000
  Estimated daily impressions: 15,000 – 22,000
  Estimated CPM: $12.50 – $18.00
  Likely to deliver budget: Yes
```

Convert any CPM micro-amounts to dollars for display.

**If the audience is too small** (very low `projected_unique_users` or the API returns a 400 error indicating audience too small), warn the user and suggest:
- Broadening the age range
- Adding more platforms
- Removing restrictive targeting (artist/genre/interest)
- Switching from VIDEO to AUDIO format (lower thresholds)
- Expanding geo targeting

Use AskUserQuestion to ask whether to:
1. Proceed anyway with current targeting
2. Adjust targeting (then re-estimate)
3. Cancel this ad set

Run the estimate for each ad set in the plan before proceeding to Step 3.

## Step 3: Prompt for Assets

For each ad, fetch available assets from the account:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/assets?limit=50&sort_direction=DESC"
```

Present audio/video assets and image assets separately in tables, and ask the user to pick:
- **asset_id** — the creative (must match the ad set's `asset_format`: audio for AUDIO, video for VIDEO, etc.)
- **logo_asset_id** — a logo image
- **companion_asset_id** — a companion image (required for AUDIO format ads)

## Step 4: Execute API Calls Sequentially

Execute each step in order, passing IDs forward from each response.

### 4a. Create Campaign

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"...","objective":"..."}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns"
```

Extract the campaign `id` from the response.

### 4b. Create Ad Sets (using campaign_id from 4a)

For each ad set:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "...",
    "campaign_id": "<from step 4a>",
    "start_time": "...",
    "end_time": "...",
    "budget": {"micro_amount": ..., "type": "..."},
    "asset_format": "...",
    "category": "ADV_X_Y",
    "targets": {
      "age_ranges": [{"min": ..., "max": ...}],
      "geo_targets": {"country_code": "..."},
      "platforms": ["ANDROID", "DESKTOP", "IOS"],
      "placements": ["MUSIC"]
    },
    "bid_strategy": "MAX_BID",
    "bid_micro_amount": ...,
    "pacing": "PACING_EVEN",
    "delivery": "ON"
  }' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets"
```

Extract each ad set `id` for use in ad creation.

### 4c. Create Ads (using ad_set_id from 4b)

For each ad:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "...",
    "ad_set_id": "<from step 4b>",
    "tagline": "...",
    "advertiser_name": "...",
    "assets": {
      "asset_id": "...",
      "logo_asset_id": "...",
      "companion_asset_id": "..."
    },
    "call_to_action": {
      "key": "SHOP_NOW",
      "clickthrough_url": "https://..."
    },
    "delivery": "ON"
  }' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads"
```

## Step 5: Summary

After all entities are created, display a final summary table:

| Entity | ID | Name | Status |
|--------|----|------|--------|
| Campaign | `uuid` | ... | ... |
| Ad Set 1 | `uuid` | ... | ... |
| ↳ Ad 1 | `uuid` | ... | ... |
| Ad Set 2 | `uuid` | ... | ... |
| ↳ Ad 2 | `uuid` | ... | ... |

## Execution Behavior

- If `auto_execute` is `true`, execute each API call directly after presenting the plan.
- If `auto_execute` is `false`, present the full plan and ask for confirmation before
  executing. Then execute all calls in sequence without additional confirmation per call.
- Always check the `HTTP_STATUS:` line from curl output to determine success or failure before interpreting the response body.
- On error, show the error message and stop. Do not continue creating dependent entities if a parent fails. Never automatically retry a POST — if a campaign/ad set/ad creation fails with a 5xx, check if the entity was actually created (e.g., list campaigns) before suggesting a retry.

## Critical Schema Notes

These are non-obvious API requirements that MUST be followed:

1. **`bid_strategy`** is a plain STRING enum, NOT an object. Valid: `MAX_BID`, `COST_PER_RESULT`, `UNSET`
2. **`geo_targets`** is a flat object `{"country_code": "US"}`, NOT an array of objects
3. **`platforms`** valid values are `ANDROID`, `DESKTOP`, `IOS` — NOT "MOBILE" or "CONNECTED_DEVICE"
4. **`category`** is required on ad sets — must be a valid `ADV_X_Y` code from `GET /ad_categories`
5. **`end_time`** is required when budget type is `LIFETIME`
6. **`companion_asset_id`** is required when creating ads for AUDIO ad sets
7. **`call_to_action`** uses field name `key` (not `type`) and `clickthrough_url` (not `url`)
8. Budget amounts must be in **micro-units** (multiply dollar amount by 1,000,000)
9. **Min audience thresholds** apply — VIDEO format may require broader targeting than AUDIO. If you get a "Min audience threshold was not met" error, suggest expanding the age range or switching format.
