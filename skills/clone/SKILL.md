---
name: clone
description: Clone an existing Spotify Ads API campaign or ad set — duplicate the full hierarchy (campaign, ad sets, ads) with optional modifications to name, dates, budget, or targeting.
argument-hint: "campaign <campaign_id> | ad-set <ad_set_id>"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Campaign & Ad Set Cloning

Clone an existing campaign or ad set by reading its full hierarchy and recreating it with optional modifications.

**Note:** If the goal is to _edit_ an existing campaign rather than _duplicate_ it, use `/spotify-ads-api:drafts draft-from <campaign_id>` instead — this creates a draft copy of the live entity that can be edited and re-published.

## Setup

1. Read `access_token`, `ad_account_id`, and `auto_execute` from the active platform settings file:
   - Codex: prefer `.codex/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.gemini/spotify-ads-api.local.md`.
   - Claude: prefer `.claude/spotify-ads-api.local.md`, then fall back to `.codex/spotify-ads-api.local.md`, then `.gemini/spotify-ads-api.local.md`.
   - Gemini: prefer `.gemini/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.codex/spotify-ads-api.local.md`.
2. Base URL: `https://api-partner.spotify.com/ads/v3`
3. If no settings file exists, instruct the user to run the configure skill first (`/spotify-ads-api:configure` on Claude/Codex, `/configure` on Gemini).
4. Read the active platform manifest for the plugin `version`: `.codex-plugin/plugin.json` on Codex, `.claude-plugin/plugin.json` on Claude, or `gemini-extension.json` (extension root) on Gemini.
5. Set `SDK_PRODUCT` to `codex-plugin` on Codex, `claude-code-plugin` on Claude, or `gemini-cli-extension` on Gemini. Set `SDK_HEADER="X-Spotify-Ads-Sdk: $SDK_PRODUCT/$PLUGIN_VERSION"` and include `-H "$SDK_HEADER"` on all API requests.

## Parsing Arguments

- `campaign <campaign_id>` → Clone a full campaign hierarchy (campaign + ad sets + ads)
- `ad-set <ad_set_id>` → Clone a single ad set and its ads into an existing campaign
- If no argument, ask the user which entity to clone.

---

## Clone Campaign (`campaign <campaign_id>`)

### Step 1: Read Source Hierarchy

#### Fetch the source campaign

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns/$CAMPAIGN_ID"
```

#### Fetch all ad sets under the campaign

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets?campaign_ids=$CAMPAIGN_ID&limit=50&sort_direction=DESC"
```

Paginate with `offset` if `total_results > 50`.

#### Fetch all ads under the campaign

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads?campaign_ids=$CAMPAIGN_ID&limit=50&sort_direction=DESC"
```

Paginate with `offset` if `total_results > 50`.

### Step 2: Display Source Tree

Present the source hierarchy in tree format:

```
Source: "Summer Promo" (REACH) — campaign_id: abc-123
├── Ad Set: "US 18-34 Audio" (AUDIO, $75/day, US, ages 18-34, Jun 1 – Jun 30)
│   ├── Ad: "30s Spot A" → SHOP_NOW → example.com [APPROVED]
│   └── Ad: "30s Spot B" → LEARN_MORE → example.com [APPROVED]
└── Ad Set: "US 25-54 Video" (VIDEO, $50/day, US, ages 25-54, Jun 1 – Jun 30)
    ├── Ad: "15s Video" → WATCH_NOW → example.com [APPROVED]
    └── Ad: "Old Creative" → SHOP_NOW → example.com [ARCHIVED] ← will be skipped
```

Note how many entities will be cloned and how many will be skipped (ARCHIVED or REJECTED ads are skipped by default).

### Step 3: Ask for Modifications

Ask the user what to change. Default: clone as-is with " (Copy)" appended to names.

**Modification options:**
- **Name**: New campaign name (default: `"{original name} (Copy)"`)
- **Dates**: New `start_time` and `end_time` for all ad sets. If the original dates are in the past, **require** new dates — the clone will fail with past dates.
- **Budget**: Adjust budget for all ad sets. Options:
  - Same as original
  - Set all to a specific amount
  - Increase/decrease by a percentage
- **Targeting**: Change geo, age range, platforms, or genders across all ad sets. Modifications apply to all ad sets uniformly. For per-ad-set changes, suggest cloning individual ad sets.
- **Ad set filter**: Optionally exclude specific ad sets from the clone.

### Step 4: Validate Before Execution

#### Date validation

If the user does not change dates and the source `start_time` is in the past, warn:
- If `start_time` is in the past but `end_time` is in the future: "The cloned ad sets will start delivering immediately."
- If `end_time` is in the past: "Source dates have passed. New dates are required for the clone."

#### Asset validation

For each ad that will be cloned, check that the referenced assets (`asset_id`, `logo_asset_id`, `companion_asset_id`) still exist and are in READY status:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/assets/$ASSET_ID"
```

If any asset is ARCHIVED or REJECTED, warn the user and ask whether to skip that ad or select a replacement asset.

#### Budget type validation

If budget type is LIFETIME and the user changed dates, verify that `end_time` is still provided — LIFETIME budgets require an end time.

#### Audience estimate validation

If targeting, dates, objective, bid, or budget changed for any cloned ad set, run a pre-flight audience estimate before creating it:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "ad_account_id": "<AD_ACCOUNT_ID>",
    "start_date": "<start_time>",
    "asset_format": "<AUDIO|VIDEO|IMAGE|CATALOG>",
    "objective": "<campaign_objective>",
    "bid_strategy": "<MAX_BID|COST_PER_RESULT|AUTOBID|UNSET>",
    "bid_micro_amount": <bid>,
    "budget": {"micro_amount": <budget>, "type": "<DAILY|LIFETIME>", "currency": "USD"},
    "targets": { <SAME_OR_MODIFIED_TARGETS> }
  }' \
  "$BASE_URL/estimates/audience"
```

If the API returns a min-audience-threshold error, pause before creating that ad set and suggest broader targeting or a lower-threshold format.

### Step 5: Present Clone Plan

Show the full plan with changes highlighted:

```
Clone Plan:
Campaign: "Summer Promo (Copy)" (REACH) ← name changed
├── Ad Set: "US 18-34 Audio (Copy)" (AUDIO, $90/day ← was $75, US, ages 18-34, Jul 1 – Jul 31 ← was Jun 1-30)
│   ├── Ad: "30s Spot A" → SHOP_NOW → example.com
│   └── Ad: "30s Spot B" → LEARN_MORE → example.com
└── Ad Set: "US 25-54 Video (Copy)" (VIDEO, $60/day ← was $50, US, ages 25-54, Jul 1 – Jul 31)
    └── Ad: "15s Video" → WATCH_NOW → example.com

Entities to create: 1 campaign, 2 ad sets, 3 ads
Skipped: 1 archived ad ("Old Creative")
```

Ask for confirmation before executing.

### Step 6: Execute Sequentially

Create entities in dependency order, passing IDs forward.

#### 6a. Create campaign

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"name":"Summer Promo (Copy)","objective":"REACH"}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns"
```

Extract the new campaign `id` from the response. If this fails, stop — no dependent entities can be created.

#### 6b. Create ad sets (using new campaign_id)

For each source ad set (excluding any the user filtered out):

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "US 18-34 Audio (Copy)",
    "campaign_id": "<NEW_CAMPAIGN_ID>",
    "start_time": "2026-07-01T00:00:00Z",
    "end_time": "2026-07-31T23:59:59Z",
    "budget": {"micro_amount": 90000000, "type": "DAILY"},
    "asset_format": "AUDIO",
    "category": "<SAME_CATEGORY>",
    "targets": { <SAME_OR_MODIFIED_TARGETS> },
    "bid_strategy": "<SAME>",
    "bid_micro_amount": <SAME>,
    "pacing": "<SAME>",
    "delivery": "ON"
  }' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets"
```

Extract each new ad set `id`. Map source ad set IDs to new ad set IDs for use in ad creation.

If an ad set creation fails, log the error and skip its ads. Continue with remaining ad sets.

#### 6c. Create ads (using new ad_set_ids)

For each source ad (excluding ARCHIVED/REJECTED), mapped to the correct new ad set:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "30s Spot A",
    "ad_set_id": "<NEW_AD_SET_ID>",
    "tagline": "<SAME>",
    "advertiser_name": "<SAME>",
    "assets": {
      "asset_id": "<SAME>",
      "logo_asset_id": "<SAME>",
      "companion_asset_id": "<SAME>"
    },
    "call_to_action": {
      "key": "<SAME>",
      "clickthrough_url": "<SAME>"
    },
    "third_party_tracking": <SAME_IF_PRESENT>,
    "delivery": "ON"
  }' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads"
```

Only include `third_party_tracking` when it exists on the source ad. Preserve it exactly unless the user explicitly asks to remove or change tracking.

If an ad creation fails, log the error and continue with remaining ads.

### Step 7: Display Summary

```
Clone Complete:
| Entity | Source ID | New ID | Name | Status |
|--------|-----------|--------|------|--------|
| Campaign | abc-123 | def-456 | Summer Promo (Copy) | ACTIVE |
| Ad Set 1 | ... | ... | US 18-34 Audio (Copy) | ACTIVE |
| ↳ Ad 1 | ... | ... | 30s Spot A | PENDING |
| ↳ Ad 2 | ... | ... | 30s Spot B | PENDING |
| Ad Set 2 | ... | ... | US 25-54 Video (Copy) | ACTIVE |
| ↳ Ad 3 | ... | ... | 15s Video | PENDING |

Created: 1 campaign, 2 ad sets, 3 ads
Skipped: 1 archived ad
Failed: 0
```

---

## Clone Ad Set (`ad-set <ad_set_id>`)

Clone a single ad set and its ads into an existing or new campaign.

### Step 1: Read Source

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets/$AD_SET_ID"
```

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads?ad_set_ids=$AD_SET_ID&limit=50"
```

### Step 2: Ask for Target Campaign

Ask the user where to place the cloned ad set:
- Same campaign (default)
- A different existing campaign (ask for campaign_id, or list campaigns to choose from)

### Step 3: Ask for Modifications

Same modification options as campaign clone (name, dates, budget, targeting) but applied to the single ad set only.

### Step 4: Validate and Present Plan

Same validation as campaign clone (dates, assets, budget type).

### Step 5: Execute

Create the ad set, then create its ads:

```bash
# Create ad set
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{...}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets"
```

```bash
# Create each ad under the new ad set
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{...}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads"
```

### Step 6: Display Summary

Same summary format as campaign clone, but without the campaign row.

---

## Fields Copied from Source

| Entity | Fields Copied | Fields Generated/Modified |
|--------|---------------|---------------------------|
| Campaign | `objective`, `purchase_order` | `name` (appended " (Copy)"), new `id` |
| Ad Set | `asset_format`, `category`, `targets`, `bid_strategy`, `bid_micro_amount`, `pacing`, `frequency_caps` | `name`, `campaign_id`, `start_time`, `end_time`, `budget`, new `id` |
| Ad | `tagline`, `advertiser_name`, `assets`, `call_to_action`, `third_party_tracking` | `name` (kept same), `ad_set_id`, new `id` |

---

## Execution Behavior

- If `auto_execute` is `true`, execute after the user confirms the clone plan. The reading and modification steps always require user interaction.
- If `auto_execute` is `false`, present each curl command and ask for confirmation before executing.
- Always check the `HTTP_STATUS:` line from curl output to determine success or failure before interpreting the response body.
- If campaign creation fails, stop entirely — no ad sets or ads can be created without a campaign.
- If an ad set creation fails, skip its ads but continue with remaining ad sets. Show what was created and what failed in the summary.
- If an ad creation fails, continue with remaining ads. Never automatically retry POST requests — the ad may have been created despite the error. Check for it first if retrying manually.

## Cross-references

- If no existing campaign to clone, create one from scratch with `/spotify-ads-api:build-campaign`.
- After cloning, monitor the new campaign with `/spotify-ads-api:dashboard` or `/spotify-ads-api:monitor`.
- If asset issues are found, check asset status with `/spotify-ads-api:assets list` or upload new assets with `/spotify-ads-api:assets upload`.
