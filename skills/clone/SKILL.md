---
name: clone
description: Clone an existing Spotify Ads API campaign or ad set as a validated draft hierarchy by default, with optional modifications to name, dates, budget, or targeting.
argument-hint: "campaign <campaign_id> | ad-set <ad_set_id> | campaign-live | ad-set-live"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Campaign & Ad Set Cloning

Clone an existing campaign or ad set by reading its full hierarchy and recreating it as drafts with optional modifications. Nothing is published automatically.

**Note:** If the goal is to _edit_ an existing campaign rather than _duplicate_ it, use `/spotify-ads-api:drafts stage-edit campaign <campaign_id> <changes>` instead.

## Setup

Set the plugin root and define the request wrapper:

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" clone "$@"; }
```

Before the first Ads API v3 call, read and follow `$PLUGIN_ROOT/skills/api-reference/references/live-openapi.md`.

To retrieve settings values (TOKEN, AD_ACCOUNT_ID, AUTO_EXECUTE, BASE_URL, SDK_HEADER, SKILL_HEADER, PLUGIN_VERSION) for use outside API calls, run `api --env`. The output is eval-safe, so `eval $(api --env)` assigns them all.

## Parsing Arguments

- `campaign <campaign_id>` → Clone a full campaign hierarchy (campaign + ad sets + ads)
- `ad-set <ad_set_id>` → Clone a single ad set and its ads into an existing campaign
- If no argument, ask the user which entity to clone.

---

## Clone Campaign (`campaign <campaign_id>`)

### Step 1: Read Source Hierarchy

#### Fetch the source campaign

```bash
api GET "ad_accounts/{ad_account_id}/campaigns/$CAMPAIGN_ID"
```

#### Fetch all ad sets under the campaign

```bash
api GET "ad_accounts/{ad_account_id}/ad_sets?campaign_ids=$CAMPAIGN_ID&limit=50&sort_direction=DESC"
```

Paginate with `offset` if `total_results > 50`.

#### Fetch all ads under the campaign

```bash
api GET "ad_accounts/{ad_account_id}/ads?campaign_ids=$CAMPAIGN_ID&limit=50&sort_direction=DESC"
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
api GET "ad_accounts/{ad_account_id}/assets/$ASSET_ID"
```

If any asset is ARCHIVED or REJECTED, warn the user and ask whether to skip that ad or select a replacement asset.

#### Budget type validation

If budget type is LIFETIME and the user changed dates, verify that `end_time` is still provided — LIFETIME budgets require an end time.

#### Audience estimate validation

If targeting, dates, objective, bid, or budget changed for any cloned ad set, run a pre-flight audience estimate before creating it:

```bash
api POST "estimates/audience" \
  '{
    "ad_account_id": "<AD_ACCOUNT_ID>",
    "start_date": "<start_time>",
    "asset_format": "<AUDIO|VIDEO|IMAGE|CATALOG>",
    "objective": "<campaign_objective>",
    "bid_strategy": "<MAX_BID|COST_PER_RESULT|AUTOBID|UNSET>",
    "bid_micro_amount": <bid>,
    "budget": {"micro_amount": <budget>, "type": "<DAILY|LIFETIME>", "currency": "<ad account billing currency>"},
    "targets": { <SAME_OR_MODIFIED_TARGETS> }
  }'
```

If the API returns a min-audience-threshold error, pause before creating that ad set and suggest broader targeting or a lower-threshold format.

### Step 4.5: Validate the Clone Against Ad Product Rules

Read and follow
`$PLUGIN_ROOT/skills/api-reference/references/ad-product-validation.md`. Fetch the live
catalog once for the clone workflow and validate the complete destination hierarchy,
including user modifications, runtime estimates, and referenced assets.

Resolve the product from the **new campaign request**. Preserve a known source
`CONTENT` or `FPMNG` product only when the destination request explicitly includes that
product; omit `ad_product` for the default `AUCTION` flow. Do not validate against the
source product while creating a different destination product.

Apply assistant-inferred compliant adjustments before showing the clone plan. Surface
only incompatible explicit choices; do not print a per-field checklist.

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

### Step 6: Create Drafts Sequentially

Create entities in dependency order, passing IDs forward.

#### 6a. Create campaign

For a destination CONTENT or FPMNG campaign, include that explicit `ad_product` in the
request. For the default AUCTION flow, omit `ad_product`.

```bash
api POST "ad_accounts/{ad_account_id}/drafts/campaigns" \
  '{"name":"Summer Promo (Copy)","delivery_goal_group":"AWARENESS"}'
```

Copy the source `delivery_goal_group` when present. If the source only exposes the deprecated `objective`, map it to `delivery_goal_group` using the mapping in the drafts skill; do not copy `objective` into the new draft.

Extract the new campaign `id` from the response. If this fails, stop — no dependent entities can be created.

#### 6b. Create ad sets (using new campaign_id)

For each source ad set, excluding any the user filtered out:

```bash
api POST "ad_accounts/{ad_account_id}/drafts/ad_sets" \
  '{
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
  }'
```

Extract each new ad set `id`. Map source ad set IDs to new ad set IDs for use in ad creation.

If an ad set creation fails, log the error and skip its ads. Continue with remaining ad sets.

#### 6c. Create ads (using new ad_set_ids)

For each source ad, excluding ARCHIVED/REJECTED, mapped to the correct new ad set:

```bash
api POST "ad_accounts/{ad_account_id}/drafts/ads" \
  '{
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
  }'
```

Only include `third_party_tracking` when it exists on the source ad. Preserve it exactly unless the user explicitly asks to remove or change tracking.

If an ad creation fails, log the error and continue with remaining ads.

### Step 7: Validate and Display Summary

Fetch the new draft campaign after all child drafts are created, use its current `draft_hierarchy_version`, and run `VALIDATE`. Do not publish as part of cloning.

```
Clone Staged:
| Entity | Source ID | New ID | Name | Status |
|--------|-----------|--------|------|--------|
| Campaign | abc-123 | def-456 | Summer Promo (Copy) | DRAFT |
| Ad Set 1 | ... | ... | US 18-34 Audio (Copy) | DRAFT |
| ↳ Ad 1 | ... | ... | 30s Spot A | DRAFT |
| ↳ Ad 2 | ... | ... | 30s Spot B | DRAFT |
| Ad Set 2 | ... | ... | US 25-54 Video (Copy) | DRAFT |
| ↳ Ad 3 | ... | ... | 15s Video | DRAFT |

Staged: 1 campaign, 2 ad sets, 3 ads
Skipped: 1 archived ad
Failed: 0
Validation: Passed
Published: No
```

---

## Clone Ad Set (`ad-set <ad_set_id>`)

Clone a single ad set and its ads into an existing or new campaign.

### Step 1: Read Source

```bash
api GET "ad_accounts/{ad_account_id}/ad_sets/$AD_SET_ID"
```

```bash
api GET "ad_accounts/{ad_account_id}/ads?ad_set_ids=$AD_SET_ID&limit=50"
```

### Step 2: Ask for Target Campaign

Ask the user where to place the cloned ad set:
- Same campaign (default)
- A different existing campaign (ask for campaign_id, or list campaigns to choose from)

Create or reuse a draft from the selected published target campaign before adding the cloned draft ad set. If a draft already exists, disclose its pending state before adding to it.

### Step 3: Ask for Modifications

Same modification options as campaign clone (name, dates, budget, targeting) but applied to the single ad set only.

### Step 4: Validate and Present Plan

Apply the same date, asset, budget, and audience checks as the campaign clone. Read and
follow `$PLUGIN_ROOT/skills/api-reference/references/ad-product-validation.md`, fetch
the catalog once for this clone workflow, and resolve the **target campaign's** product.
Validate the final new ad set and ads against that destination product before presenting
the existing confirmation. Do not print a per-field checklist or add another gate.

### Step 5: Execute

Create the draft ad set, then create its draft ads:

```bash
# Create ad set
api POST "ad_accounts/{ad_account_id}/drafts/ad_sets" \
  '{...}'
```

```bash
# Create each ad under the new ad set
api POST "ad_accounts/{ad_account_id}/drafts/ads" \
  '{...}'
```

### Step 6: Validate and Display Summary

Fetch the target draft campaign's current version, validate it, and use the same staged summary format as campaign clone, but without a newly cloned campaign row.

---

## Fields Copied from Source

| Entity | Fields Copied | Fields Generated/Modified |
|--------|---------------|---------------------------|
| Campaign | `delivery_goal_group`, `purchase_order` | `name` (appended " (Copy)"), new `id`; map a legacy source `objective` to `delivery_goal_group` |
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
- Never publish a clone automatically. Publishing is a separate operation and requires explicit confirmation immediately before `PUBLISH`.
- Use published creation endpoints only when the user explicitly asks to clone directly to live entities. If a direct write is denied, do not infer that the credentials are read-only; offer the draft clone workflow instead.

## Cross-references

- If no existing campaign to clone, create one from scratch with `/spotify-ads-api:build-campaign`.
- After cloning, monitor the new campaign with `/spotify-ads-api:dashboard` or `/spotify-ads-api:monitor`.
- If asset issues are found, check asset status with `/spotify-ads-api:assets list` or upload new assets with `/spotify-ads-api:assets upload`.
