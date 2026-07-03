---
name: bulk
description: Apply batch operations to multiple Spotify Ads API entities — pause or resume ad sets, update budgets, toggle ad delivery, swap creatives, or archive campaigns, ad sets, and ads.
argument-hint: "pause | resume | budget | delivery | archive | creative"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Bulk Operations

Apply batch changes to multiple entities in a single workflow. All operations follow the same pattern: list entities, select targets, confirm changes, apply sequentially.

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

Parse the user's argument to determine the operation:
- `pause` — Pause multiple active ad sets or campaigns
- `resume` — Resume paused ad sets or campaigns
- `budget` — Update budgets across selected ad sets
- `delivery` — Toggle ad delivery ON/OFF
- `archive` — Archive multiple entities
- `creative` — Swap creative assets across ads
- If no argument, ask the user which operation.

All operations optionally accept a campaign filter: `pause --campaign <campaign_id>` narrows the entity list to a specific campaign.

---

## Selection Pattern

All operations follow this pattern:

### 1. List candidates

Fetch entities matching the operation's criteria. Present as a numbered table:

```
Active Ad Sets (5 found):
| # | ID | Name | Campaign | Budget | Format |
|---|----|------|----------|--------|--------|
| 1 | abc... | US 18-34 Audio | Summer Promo | $75/day | AUDIO |
| 2 | def... | US 25-54 Video | Summer Promo | $50/day | VIDEO |
| 3 | ghi... | UK All Audio | Q2 Brand | $100/day | AUDIO |
| 4 | jkl... | CA 18-44 Audio | Q2 Brand | $60/day | AUDIO |
| 5 | mno... | US All Display | Podcast Launch | $40/day | IMAGE |
```

### 2. Select targets

Ask the user to select entities. Support these selection formats:
- Individual numbers: `1, 3, 5`
- Ranges: `1-3`
- All: `all`
- Mixed: `1-3, 5`

### 3. Confirm changes

Show a summary of what will change. For budget operations, show before/after values. For status changes, show entity names and the target state.

### 4. Apply sequentially

Execute PATCH requests one at a time. Report success or failure for each entity. Continue on partial failure — do not stop the batch if one entity fails.

### 5. Show results

Display a final summary table:

```
Bulk Pause Results:
| Ad Set | Status | Result |
|--------|--------|--------|
| US 18-34 Audio | PAUSED | Success |
| UK All Audio | PAUSED | Success |
| US All Display | — | Failed: 403 Forbidden |

2/3 operations succeeded.
```

---

## Operations

### `pause`

Pause multiple active ad sets or campaigns.

#### List candidates

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets?statuses=ACTIVE&limit=50&sort_direction=DESC"
```

To filter by campaign: add `&campaign_ids=$CAMPAIGN_ID`.

To pause campaigns instead of ad sets, ask the user first, then:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns?statuses=ACTIVE&limit=50&sort_direction=DESC"
```

#### Apply

For each selected ad set:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"status":"PAUSED"}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets/$AD_SET_ID"
```

For campaigns, use the campaigns endpoint instead.

Skip entities that are already PAUSED — note them as "Already paused, skipped" in the results.

---

### `resume`

Resume paused ad sets or campaigns.

#### List candidates

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets?statuses=PAUSED&limit=50&sort_direction=DESC"
```

#### Apply

For each selected ad set:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"status":"ACTIVE"}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets/$AD_SET_ID"
```

---

### `budget`

Update budgets across multiple ad sets.

#### List candidates

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets?limit=50&sort_direction=DESC"
```

Present the table with current budget amounts (convert `micro_amount` ÷ 1,000,000 to dollars) and budget type (DAILY/LIFETIME).

#### Ask for budget change

After selection, ask how to change the budget:
- **Set to**: "Set all selected ad sets to $X/day" or "$X lifetime"
- **Increase by %**: "Increase by 20%" — multiply each ad set's current budget by 1.2
- **Increase by $**: "Increase by $25" — add $25 (25,000,000 micro) to each
- **Decrease by %**: "Decrease by 15%"
- **Decrease by $**: "Decrease by $10"

#### Show before/after

```
Budget changes (+20%):
| Ad Set | Budget Type | Current | New |
|--------|-------------|---------|-----|
| US 18-34 Audio | DAILY | $75.00 | $90.00 |
| UK All Audio | DAILY | $100.00 | $120.00 |

Proceed with these changes?
```

#### Apply

For each selected ad set:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"budget":{"micro_amount":<NEW_MICRO_AMOUNT>,"type":"<DAILY|LIFETIME>"}}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets/$AD_SET_ID"
```

Always convert dollar amounts to micro-amounts by multiplying by 1,000,000.

---

### `delivery`

Toggle ad delivery ON or OFF across multiple ads.

#### List candidates

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads?limit=50&sort_direction=DESC"
```

To filter by campaign or ad set: add `&campaign_ids=$CAMPAIGN_ID` or `&ad_set_ids=$AD_SET_ID`.

Present the table showing current delivery status (ON/OFF), ad name, ad set name, and status.

#### Ask for target state

Ask the user: toggle all selected to ON, or toggle all to OFF?

#### Apply

For each selected ad:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"delivery":"ON"}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads/$AD_ID"
```

Skip ads already in the target delivery state.

---

### `archive`

Archive multiple entities. This is effectively permanent — there is no unarchive for campaigns, ad sets, or ads.

#### Ask entity type

Ask the user: "What do you want to archive — campaigns, ad sets, or ads?"

#### List candidates

Fetch non-archived entities of the selected type:

```bash
# For ad sets:
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets?statuses=ACTIVE&statuses=PAUSED&limit=50&sort_direction=DESC"
```

#### Confirm with warning

Before applying, warn: "Archiving is effectively permanent. Archived entities cannot be reactivated. Are you sure?"

#### Apply

For each selected entity:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"status":"ARCHIVED"}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets/$AD_SET_ID"
```

---

### `creative`

Swap creative assets across multiple ads.

**Important**: The `PATCH /ads/{id}` endpoint does **not** support updating asset fields. To swap creative, this operation must:
1. Read the existing ad's full configuration
2. Create a **new** ad with the same configuration but different assets
3. Archive the old ad

This means creative swaps produce new ad IDs, new approval cycles, and reset delivery metrics. Warn the user about this before proceeding. Also preserve third-party tracking exactly from the original ad unless the user explicitly asks to remove or change tracking.

#### Step 1: List ads

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads?limit=50&sort_direction=DESC"
```

Present table showing ad name, current asset, ad set, delivery status.

#### Step 2: List available assets

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/assets?statuses=READY&limit=50&sort_direction=DESC"
```

Present table of available assets filtered to READY status.

#### Step 3: Select ads and new asset

Ask the user to select which ads to update and which new asset to use. The new asset must match the ad set's `asset_format` (AUDIO, VIDEO, or IMAGE).

#### Step 4: For each selected ad, swap

**Read the existing ad:**

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads/$AD_ID"
```

**Create the replacement ad** with the same fields but new asset_id:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "<same_name>",
    "ad_set_id": "<same_ad_set_id>",
    "tagline": "<same_tagline>",
    "advertiser_name": "<same_advertiser_name>",
    "assets": {
      "asset_id": "<NEW_ASSET_ID>",
      "logo_asset_id": "<same_logo>",
      "companion_asset_id": "<same_companion>"
    },
    "call_to_action": {
      "key": "<same_key>",
      "clickthrough_url": "<same_url>"
    },
    "third_party_tracking": <same_third_party_tracking_if_present>,
    "delivery": "<same_delivery>"
  }' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads"
```

Only include `third_party_tracking` when it exists on the source ad. If tracking cannot be copied, ask the user before archiving the original ad.

**Archive the old ad:**

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"status":"ARCHIVED"}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads/$OLD_AD_ID"
```

#### Results table

```
Creative Swap Results:
| Original Ad | New Ad ID | Asset | Result |
|-------------|-----------|-------|--------|
| 30s Spot A (abc...) | def... | new-audio.mp3 | Success |
| 30s Spot B (ghi...) | jkl... | new-audio.mp3 | Success |

2/2 swaps completed. Old ads archived. New ads are in PENDING approval status.
```

---

## Execution Behavior

- If `auto_execute` is `true`, execute after the user confirms the change summary. The listing and selection steps always require user interaction regardless of auto_execute.
- If `auto_execute` is `false`, present each curl command and ask for confirmation before executing.
- Always check the `HTTP_STATUS:` line from curl output to determine success or failure before interpreting the response body.
- On error for any individual entity, log the error and continue with remaining entities. Never automatically retry POST or PATCH requests.
- Display a final summary showing success/failure count and per-entity results.
- For accounts with >50 entities, show the first 50 and suggest using a campaign filter (`--campaign <id>`) to narrow results.

## Cross-references

- Before bulk operations, review performance with `/spotify-ads-api:dashboard`.
- For individual entity changes, use `/spotify-ads-api:campaigns update` or `/spotify-ads-api:ads ad-sets update`.
- To see available assets for creative swaps, use `/spotify-ads-api:assets list`.
