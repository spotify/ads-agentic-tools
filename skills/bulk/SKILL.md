---
name: bulk
description: Stage batch changes to Spotify Ads API campaigns, ad sets, and ads through drafts by default — pause, resume, budgets, delivery, archive, creative, and tracking changes. Use direct live writes only when explicitly requested.
argument-hint: "pause | resume | budget | delivery | archive | creative | tracking"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Bulk Operations

Apply batch changes to multiple entities in a single workflow. Campaign hierarchy changes are staged through drafts by default, grouped and validated by parent campaign, and never published automatically.

## Setup

Set the plugin root and define the request wrapper:

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" bulk "$@"; }
```

To retrieve settings values (TOKEN, AD_ACCOUNT_ID, AUTO_EXECUTE, BASE_URL) for use outside API calls, run `api --env`.

## Parsing Arguments

Parse the user's argument to determine the operation:
- `pause` — Pause multiple active ad sets or campaigns
- `resume` — Resume paused ad sets or campaigns
- `budget` — Update budgets across selected ad sets
- `delivery` — Toggle ad delivery ON/OFF
- `archive` — Archive multiple entities
- `creative` — Swap creative assets across ads
- `tracking` — Update third-party tracking across ads
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

### 4. Stage changes

Group selected entities by parent campaign. For each target, check for an existing same-ID draft and disclose pending changes. If none exists, create a draft from the published entity, then PATCH the draft endpoint. Preserve fields the user did not request to change.

After staging all selected changes, fetch each affected draft campaign's current `draft_hierarchy_version` and validate once per campaign. Continue on per-entity staging failures, but do not validate a campaign until all successful edits for that campaign are staged.

### 5. Show results

Display a final summary table:

```
Bulk Pause Staging Results:
| Ad Set | Status | Result |
|--------|--------|--------|
| US 18-34 Audio | PAUSED | Staged; validation passed |
| UK All Audio | PAUSED | Staged; validation passed |
| US All Display | — | Failed: error details |

2/3 changes staged. Nothing was published.
```

---

## Operations

### `pause`

Pause multiple active ad sets or campaigns.

#### List candidates

```bash
api GET "ad_accounts/{ad_account_id}/ad_sets?statuses=ACTIVE&limit=50&sort_direction=DESC"
```

To filter by campaign: add `&campaign_ids=$CAMPAIGN_ID`.

To pause campaigns instead of ad sets, ask the user first, then:

```bash
api GET "ad_accounts/{ad_account_id}/campaigns?statuses=ACTIVE&limit=50&sort_direction=DESC"
```

#### Apply

For each selected ad set, create or reuse its draft, then:

```bash
api PATCH "ad_accounts/{ad_account_id}/drafts/ad_sets/$AD_SET_ID" \
  '{"status":"PAUSED"}'
```

For campaigns, create or reuse the campaign draft and PATCH `/drafts/campaigns/{id}` instead.

Skip entities that are already PAUSED — note them as "Already paused, skipped" in the results.

---

### `resume`

Resume paused ad sets or campaigns.

#### List candidates

```bash
api GET "ad_accounts/{ad_account_id}/ad_sets?statuses=PAUSED&limit=50&sort_direction=DESC"
```

#### Apply

For each selected ad set, create or reuse its draft, then:

```bash
api PATCH "ad_accounts/{ad_account_id}/drafts/ad_sets/$AD_SET_ID" \
  '{"status":"ACTIVE"}'
```

---

### `budget`

Update budgets across multiple ad sets.

#### List candidates

```bash
api GET "ad_accounts/{ad_account_id}/ad_sets?limit=50&sort_direction=DESC"
```

Present the table with current budget amounts (convert `micro_amount` ÷ 1,000,000 to the ad account's billing currency) and budget type (DAILY/LIFETIME).

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

For each selected ad set, create or reuse its draft, then:

```bash
api PATCH "ad_accounts/{ad_account_id}/drafts/ad_sets/$AD_SET_ID" \
  '{"budget":{"micro_amount":<NEW_MICRO_AMOUNT>,"type":"<DAILY|LIFETIME>"}}'
```

Always convert amounts to micro-amounts (multiply by 1,000,000).

---

### `delivery`

Toggle ad delivery ON or OFF across multiple ads.

#### List candidates

```bash
api GET "ad_accounts/{ad_account_id}/ads?limit=50&sort_direction=DESC"
```

To filter by campaign or ad set: add `&campaign_ids=$CAMPAIGN_ID` or `&ad_set_ids=$AD_SET_ID`.

Present the table showing current delivery status (ON/OFF), ad name, ad set name, and status.

#### Ask for target state

Ask the user: toggle all selected to ON, or toggle all to OFF?

#### Apply

For each selected ad, create or reuse its draft, then:

```bash
api PATCH "ad_accounts/{ad_account_id}/drafts/ads/$AD_ID" \
  '{"delivery":"ON"}'
```

Skip ads already in the target delivery state.

---

### `archive`

Stage archival of multiple entities. The draft can be reviewed or deleted before publishing, but publishing an archive is effectively permanent because campaigns, ad sets, and ads cannot be unarchived.

#### Ask entity type

Ask the user: "What do you want to archive — campaigns, ad sets, or ads?"

#### List candidates

Fetch non-archived entities of the selected type:

```bash
# For ad sets:
api GET "ad_accounts/{ad_account_id}/ad_sets?statuses=ACTIVE&statuses=PAUSED&limit=50&sort_direction=DESC"
```

#### Confirm with warning

Before staging, warn: "Publishing these staged archive changes will be effectively permanent. Archived entities cannot be reactivated. Stage these changes for review?"

#### Apply

For each selected entity, create or reuse its draft, then:

```bash
api PATCH "ad_accounts/{ad_account_id}/drafts/ad_sets/$AD_SET_ID" \
  '{"status":"ARCHIVED"}'
```

---

### `tracking`

Update `third_party_tracking` across multiple ads. This is the default workflow for requests to fix, add, remove, or replace impression, click, quartile, completion, or viewability trackers.

#### Step 1: Read and select ads

List candidates, then fetch every selected published ad so the current tracking array is available. Present the existing trackers with `measurement_event`, `measurement_partner`, and a safely shortened URL.

#### Step 2: Build complete intended arrays

Apply the user's requested transformations while preserving entries they did not ask to remove or replace. Strip or rewrite URL macros only as explicitly requested. Set `measurement_event` on every entry; use `CLICKED` for click trackers and `IMPRESSION` for impression trackers.

Show a before/after summary and ask for confirmation.

#### Step 3: Stage each update

For each selected ad, check for an existing same-ID draft. Create one from the published ad only after a 404, then PATCH the draft with the complete intended tracking array:

```bash
api GET "ad_accounts/{ad_account_id}/drafts/ads/$AD_ID"
api POST "ad_accounts/{ad_account_id}/ads/$AD_ID/drafts" # only after draft GET returns 404
api PATCH "ad_accounts/{ad_account_id}/drafts/ads/$AD_ID" \
  '{"third_party_tracking":[...]}'
```

Resolve the parent draft campaign for every ad, group by campaign, and validate once per affected campaign after all successful tracking patches are staged. Report that nothing was published.

---

### `creative`

Swap creative assets across multiple ads.

The live `PATCH /ads/{id}` endpoint does not support updating asset fields, but draft ads do. Create or reuse a same-ID draft for each selected published ad and update its `assets` field. Preserve third-party tracking exactly unless the user explicitly asks to remove or change tracking.

#### Step 1: List ads

```bash
api GET "ad_accounts/{ad_account_id}/ads?limit=50&sort_direction=DESC"
```

Present table showing ad name, current asset, ad set, delivery status.

#### Step 2: List available assets

```bash
api GET "ad_accounts/{ad_account_id}/assets?statuses=READY&limit=50&sort_direction=DESC"
```

Present table of available assets filtered to READY status.

#### Step 3: Select ads and new asset

Ask the user to select which ads to update and which new asset to use. The new asset must match the ad set's `asset_format` (AUDIO, VIDEO, or IMAGE).

#### Step 4: For each selected ad, stage the swap

**Read the existing ad:**

```bash
api GET "ad_accounts/{ad_account_id}/ads/$AD_ID"
```

**Check for or create the draft:**

```bash
api GET "ad_accounts/{ad_account_id}/drafts/ads/$AD_ID"
api POST "ad_accounts/{ad_account_id}/ads/$AD_ID/drafts" # only after draft GET returns 404
```

**Update the draft ad** with the complete intended assets object:

```bash
api PATCH "ad_accounts/{ad_account_id}/drafts/ads/$AD_ID" \
  '{
    "assets": {
      "asset_id": "<NEW_ASSET_ID>",
      "logo_asset_id": "<same_logo>",
      "companion_asset_id": "<same_companion>"
    }
  }'
```

Resolve each draft ad's parent draft campaign and validate once per affected campaign after all swaps are staged. Do not archive the published ad and do not create a replacement live ad.

#### Results table

```
Creative Swap Results:
| Draft Ad | Published ID | Asset | Result |
|----------|--------------|-------|--------|
| 30s Spot A | abc... | new-audio.mp3 | Staged; validation passed |
| 30s Spot B | ghi... | new-audio.mp3 | Staged; validation passed |

2/2 swaps staged. Nothing was published.
```

---

## Execution Behavior

- If `auto_execute` is `true`, stage and validate after the user confirms the change summary. The listing and selection steps always require user interaction regardless of auto_execute.
- If `auto_execute` is `false`, present each curl command and ask for confirmation before executing.
- Always check the `HTTP_STATUS:` line from curl output to determine success or failure before interpreting the response body.
- On error for any individual entity, log the error and continue with remaining entities. Never automatically retry POST or PATCH requests.
- Display a final summary showing success/failure count and per-entity results.
- For accounts with >50 entities, show the first 50 and suggest using a campaign filter (`--campaign <id>`) to narrow results.
- Never publish staged bulk changes automatically. Publishing is a separate operation and requires explicit confirmation immediately before each affected campaign's `PUBLISH` request.
- Only use direct published endpoints when the user explicitly asks for immediate/direct live changes. If such a request returns HTTP 403 or an edit-permission error, describe only the direct-write denial and offer draft staging; do not infer that the credentials are read-only.

## Cross-references

- Before bulk operations, review performance with `/spotify-ads-api:dashboard`.
- For individual entity changes, use `/spotify-ads-api:drafts stage-edit <campaign|ad-set|ad> <id> <changes>`.
- To see available assets for creative swaps, use `/spotify-ads-api:assets list`.
