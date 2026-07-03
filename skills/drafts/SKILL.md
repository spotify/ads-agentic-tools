---
name: drafts
description: "Create, edit, validate, and publish draft campaigns, ad sets, and ads via the Spotify Ads API. Drafts let you build a full campaign hierarchy without going live — review and iterate before publishing. Use when the user wants to draft a campaign, validate before publishing, edit drafts, list drafts, or publish drafts."
argument-hint: "build <description> | list [campaigns|ad-sets|ads] | get <campaign|ad-set|ad> <draft_id> | edit <campaign|ad-set|ad> <draft_id> | validate <draft_campaign_id> | publish <draft_campaign_id> | delete <campaign|ad-set|ad> <draft_id> | draft-from <campaign|ad-set|ad> <entity_id>"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Draft Campaign Management

Build, review, and publish campaign hierarchies using the draft workflow. Drafts are staging versions of campaigns, ad sets, and ads that can be created, edited, validated, and published as a batch — nothing goes live until you explicitly publish.

## Why Drafts

The draft flow is the **preferred** way to create campaigns because:
- **Review before going live** — build the entire hierarchy, then validate and publish in one step
- **Batch validation** — the validate action checks the entire campaign hierarchy (campaign + ad sets + ads) at once, surfacing all errors before anything is created
- **Safe iteration** — edit any part of the draft hierarchy without affecting live entities
- **Undo-friendly** — delete drafts at any time before publishing; no cleanup of live entities needed
- **Incomplete data allowed** — drafts accept partial entities (e.g., an AUDIO ad without `companion_asset_id`). Required fields are only enforced during VALIDATE or PUBLISH, so you can build the hierarchy incrementally

The alternative (direct entity creation via `/campaigns`, `/ad_sets`, `/ads`) validates at each individual API call, so errors in later entities (e.g., ads) are discovered only after the campaign and ad sets are already live. Prefer the draft flow for any new campaign creation.

## Setup

1. Read `access_token`, `ad_account_id`, and `auto_execute` from the active platform settings file:
   - Codex: prefer `.codex/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.agents/spotify-ads-api.local.md`.
   - Claude: prefer `.claude/spotify-ads-api.local.md`, then fall back to `.codex/spotify-ads-api.local.md`, then `.agents/spotify-ads-api.local.md`.
   - Antigravity: prefer `.agents/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.codex/spotify-ads-api.local.md`.
2. Base URL: `https://api-partner.spotify.com/ads/v3`
3. If no settings file exists, instruct the user to run the configure skill first (`/spotify-ads-api:configure` on Claude/Codex, `/configure` on Antigravity).
4. Read the active platform manifest for the plugin `version`: `.codex-plugin/plugin.json` on Codex, `.claude-plugin/plugin.json` on Claude, or `plugin.json` (plugin root) on Antigravity.
5. Set `SDK_PRODUCT` to `codex-plugin` on Codex, `claude-code-plugin` on Claude, or `antigravity-cli-plugin` on Antigravity. Set `SDK_HEADER="X-Spotify-Ads-Sdk: $SDK_PRODUCT/$PLUGIN_VERSION"` and include `-H "$SDK_HEADER"` on all API requests.

## Operations

Parse the user's argument to determine the operation. For `get`, `edit`, `delete`, and `draft-from`, require an entity type (`campaign`, `ad-set`, or `ad`) with the ID. If the user provides only a bare UUID, infer the type only when the current conversation makes it unambiguous; otherwise ask which draft entity type they mean.

---

### `build` — Create a Full Draft Campaign Hierarchy

Given a plain-text campaign description, create the full draft hierarchy: draft campaign → draft ad sets → draft ads. This mirrors `/spotify-ads-api:build-campaign` but creates drafts instead of live entities.

#### Step 1: Parse the Campaign Description

Extract fields exactly as documented in the `build-campaign` skill. The same field requirements, defaults, and validation guardrails apply (micro-amounts, bid_strategy as plain string, geo_targets as flat object, platform enums, etc.).

#### Step 2: Confirm the Parsed Plan

Present the plan as a visual tree, clearly labeled as **DRAFT**:

```
DRAFT Campaign: "My Campaign" (objective: REACH)
├── DRAFT Ad Set 1: "Ad Set A" (AUDIO, $75/day, US, ages 25-54, Mar 1 start)
│   └── DRAFT Ad 1: "My Ad" → SHOP_NOW → example.com
└── DRAFT Ad Set 2: "Ad Set B" (VIDEO, $500 lifetime, US, ages 18-54, Mar 4–Apr 4)
    └── DRAFT Ad 2: "My Video Ad" → LEARN_MORE → example.com
```

Ask the user to confirm or adjust before creating drafts.

#### Step 3: Prompt for Assets

Fetch available assets from the account and present them for selection, just like the `build-campaign` skill:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/assets?limit=50&sort_direction=DESC"
```

#### Step 4: Create Draft Entities Sequentially

**4a. Create Draft Campaign:**

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"name":"...","objective":"..."}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns"
```

Extract the draft campaign `id` from the response. The response includes an initial `draft_hierarchy_version`, but do not rely on that value after creating child draft ad sets or ads because any hierarchy edit can increment the version.

**4b. Create Draft Ad Sets** (using `campaign_id` = draft campaign ID from 4a):

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "campaign_id": "<draft_campaign_id from step 4a>",
    "name": "...",
    "start_time": "...",
    "end_time": "...",
    "budget": {"micro_amount": ..., "type": "..."},
    "asset_format": "...",
    "category": "ADV_X_Y",
    "targets": { ... },
    "bid_strategy": "MAX_BID",
    "bid_micro_amount": ...
  }' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/ad_sets"
```

Extract each draft ad set `id`.

**4c. Create Draft Ads** (using `ad_set_id` = draft ad set ID from 4b):

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "ad_set_id": "<draft_ad_set_id from step 4b>",
    "name": "...",
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
    }
  }' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/ads"
```

#### Step 5: Validate the Draft

After all draft entities are created, fetch the draft campaign again to get the current `draft_hierarchy_version`, then automatically run validation. Do not reuse a version captured before child draft ad sets or ads were created.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/$DRAFT_CAMPAIGN_ID"
```

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"action":"VALIDATE","draft_hierarchy_version":<version>}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/$DRAFT_CAMPAIGN_ID"
```

The `draft_hierarchy_version` must match the current value from the draft campaign response.

**If validation succeeds** (HTTP 200 with `validation_errors: null`):
- Display a success summary with the full draft hierarchy
- Ask the user: **Publish now** or **Keep as draft for later**

**If validation returns errors** (HTTP 400 with `validation_errors` array):
- Display each error with its entity type, entity ID, and message:
  ```
  Validation Errors:
  ✗ AD_SET (id: abc-123): Ad set targeting is required
  ✗ AD (id: def-456): Missing companion_asset_id for AUDIO format
  ```
- Suggest fixes for each error
- Ask the user if they want to fix the issues (for example, `edit ad-set <draft_ad_set_id>` or `edit ad <draft_ad_id>`) or delete the draft

#### Step 6: Summary

Display a final summary:

| Entity | Draft ID | Name | Status |
|--------|----------|------|--------|
| Draft Campaign | `uuid` | ... | DRAFT |
| Draft Ad Set 1 | `uuid` | ... | DRAFT |
| ↳ Draft Ad 1 | `uuid` | ... | DRAFT |

Include the `draft_hierarchy_version` and remind the user they can:
- **Validate**: `/spotify-ads-api:drafts validate <draft_campaign_id>`
- **Publish**: `/spotify-ads-api:drafts publish <draft_campaign_id>`
- **Edit**: `/spotify-ads-api:drafts edit <campaign|ad-set|ad> <draft_id>`

---

### `list` — List Drafts

List draft entities. Argument specifies which type: `campaigns`, `ad-sets`, or `ads`. Default to `campaigns`.

**List draft campaigns:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns?limit=50&sort_direction=DESC"
```

Format as table: Draft ID | Name | Status | Objective | Version | Created

Optional filters use the actual query parameter names: `campaign_ids` (repeated param), `channel`, `statuses` (repeated param), `sort_field`, `sort_direction`.

**List draft ad sets:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/ad_sets?limit=50"
```

Format as table: Draft ID | Name | Campaign ID | Status | Format | Budget

Optional filters: `campaign_ids` (repeated param), `statuses` (repeated param).

**List draft ads:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/ads?limit=50"
```

Format as table: Draft ID | Name | Ad Set ID | Status

Optional filters: `ad_set_ids` (repeated param), `statuses` (repeated param).

---

### `get <campaign|ad-set|ad> <draft_id>` — Get a Draft by ID

Use the entity type from the command to select the endpoint. If the user supplies only a bare ID, infer the type only when prior context is unambiguous; otherwise ask the user for `campaign`, `ad-set`, or `ad`.

**Draft campaign:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/$DRAFT_CAMPAIGN_ID"
```

**Draft ad set:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/ad_sets/$DRAFT_AD_SET_ID"
```

**Draft ad:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/ads/$DRAFT_AD_ID"
```

Display all fields in a readable format. Note that `draft_hierarchy_version` is only populated on campaign drafts; ad set and ad drafts return `null` for this field.

---

### `edit <campaign|ad-set|ad> <draft_id>` — Update a Draft

Use the entity type from the command to select the endpoint, then prompt the user for fields to update. The same field validations as create apply.

**Update draft campaign:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"name":"...","objective":"..."}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/$DRAFT_CAMPAIGN_ID"
```

Updatable campaign fields: `name`, `purchase_order`, `objective`, `delivery_goal_group`, `status`.

**Update draft ad set:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{...}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/ad_sets/$DRAFT_AD_SET_ID"
```

Updatable ad set fields: `name`, `start_time`, `end_time`, `budget`, `bid_micro_amount`, `bid_strategy`, `targets`, `pacing`, `asset_format`, `category`, `frequency_caps`, `cost_model`, `delivery_goal`, `promotion`, `video_delivery_formats`, `status`.

**Update draft ad:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{...}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/ads/$DRAFT_AD_ID"
```

Updatable ad fields: `name`, `advertiser_name`, `tagline`, `assets`, `asset_format`, `call_to_action`, `third_party_tracking`, `placements`, `weight`, `status`.

After updating, display the updated draft. For campaign drafts, note the new `draft_hierarchy_version`. For ad set and ad drafts, `draft_hierarchy_version` is `null` in the response — fetch the parent draft campaign to get the updated version.

---

### `validate <draft_campaign_id>` — Validate a Draft Campaign

Dry-run the publish to check for errors across the entire hierarchy (campaign + all ad sets + all ads):

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"action":"VALIDATE","draft_hierarchy_version":<version>}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/$DRAFT_CAMPAIGN_ID"
```

First, fetch the draft campaign to get the current `draft_hierarchy_version`:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/$DRAFT_CAMPAIGN_ID"
```

**Handling the response:**

- **HTTP 200** — validation passed. The response is a `PublishCampaignResult` with `validation_errors: null` and optionally `campaign` data.
- **HTTP 400** — validation failed. The response contains a `validation_errors` array of `HierarchyValidationError` objects.

Each `HierarchyValidationError` has:
- `validation_entity_type`: `CAMPAIGN`, `AD_SET`, or `AD`
- `validation_entity_id`: UUID of the failing entity
- `message`: human-readable error description

**If no validation errors (HTTP 200):**
```
✓ Draft campaign "My Campaign" passed validation.
  Campaign + 2 ad sets + 3 ads are ready to publish.

  Publish now? /spotify-ads-api:drafts publish <draft_campaign_id>
```

**If validation errors exist (HTTP 400):**
```
✗ Draft campaign "My Campaign" has validation errors:

  Entity          | ID           | Error
  AD_SET          | abc-123      | Budget micro_amount is required
  AD              | def-456      | Missing companion_asset_id for AUDIO format
  AD              | ghi-789      | call_to_action.clickthrough_url is required

Fix these issues with: /spotify-ads-api:drafts edit <campaign|ad-set|ad> <draft_id>
Then re-validate with: /spotify-ads-api:drafts validate <draft_campaign_id>
```

---

### `publish <draft_campaign_id>` — Publish a Draft Campaign

Publish the entire draft hierarchy (campaign + ad sets + ads) as live entities. Published entities retain the same IDs they had as drafts. **Always validate first** before publishing.

#### Step 1: Fetch the draft campaign to get `draft_hierarchy_version`

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/$DRAFT_CAMPAIGN_ID"
```

#### Step 2: Run validation first

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"action":"VALIDATE","draft_hierarchy_version":<version>}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/$DRAFT_CAMPAIGN_ID"
```

If validation errors exist, display them and stop. Do not publish with validation errors.

#### Step 3: Confirm with the user

Show the full draft hierarchy that will be published and ask for confirmation:

```
Ready to publish draft campaign "My Campaign":
├── Ad Set 1: "Ad Set A" (AUDIO, $75/day)
│   └── Ad 1: "My Ad"
└── Ad Set 2: "Ad Set B" (VIDEO, $500 lifetime)
    └── Ad 2: "My Video Ad"

This will create live entities. Proceed?
```

#### Step 4: Publish

Fetch the draft campaign again immediately before publishing. If the `draft_hierarchy_version` differs from the version that just passed validation, re-run validation before publishing.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/$DRAFT_CAMPAIGN_ID"
```

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"action":"PUBLISH","draft_hierarchy_version":<version>}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/$DRAFT_CAMPAIGN_ID"
```

Display the published campaign details from the response. Published entities retain the same IDs they had as drafts.

---

### `delete <campaign|ad-set|ad> <draft_id>` — Delete a Draft

Use the entity type from the command to select the endpoint. If the user supplies only a bare ID, infer the type only when prior context is unambiguous; otherwise ask.

**Delete draft campaign** (also removes associated draft ad sets and ads):
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X DELETE -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/$DRAFT_CAMPAIGN_ID"
```

**Delete draft ad set:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X DELETE -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/ad_sets/$DRAFT_AD_SET_ID"
```

**Delete draft ad:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X DELETE -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/drafts/ads/$DRAFT_AD_ID"
```

Expect a `204 No Content` response on success.

---

### `draft-from <campaign|ad-set|ad> <entity_id>` — Create a Draft from a Published Entity

Create a draft copy of an existing live campaign, ad set, or ad for editing. Use the entity type from the command to select the endpoint. This is useful for making changes to published entities via the draft → edit → validate → publish workflow.

**Draft from published campaign:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns/$CAMPAIGN_ID/drafts"
```

**Draft from published ad set:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets/$AD_SET_ID/drafts"
```

**Draft from published ad:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads/$AD_ID/drafts"
```

The draft-from-published response reuses the **same ID** as the live entity (not a new UUID). The status becomes `ACTIVE_RESTRICTED`.

For a campaign draft, the returned entity is the draft campaign used for validate/publish. For an ad set draft, use its `campaign_id` as the draft campaign ID for validate/publish. For an ad draft, fetch the draft ad set referenced by its `ad_set_id`, then use that draft ad set's `campaign_id` as the draft campaign ID.

Display the created draft and suggest next steps:
- Edit: `/spotify-ads-api:drafts edit <campaign|ad-set|ad> <draft_id>`
- Validate: `/spotify-ads-api:drafts validate <draft_campaign_id>`
- Publish: `/spotify-ads-api:drafts publish <draft_campaign_id>`

---

## Critical Schema Notes

Unlike direct entity creation, draft creation accepts incomplete data — required fields are only enforced during VALIDATE or PUBLISH actions. This is a key benefit of drafts: save work in progress and complete it later.

1. **`bid_strategy`** is a plain STRING enum, NOT an object. Valid: `MAX_BID`, `COST_PER_RESULT`, `AUTOBID`, `UNSET`
2. **`geo_targets`** is a flat object `{"country_code": "US"}`, NOT an array of objects
3. **`platforms`** valid values are `ANDROID`, `DESKTOP`, `IOS` — NOT "MOBILE" or "CONNECTED_DEVICE"
4. **`category`** is required on ad sets — must be a valid `ADV_X_Y` code from `GET /ad_categories`
5. **`end_time`** is required when budget type is `LIFETIME`
6. **`companion_asset_id`** is required for AUDIO format ads at publish/validation time, but can be omitted when creating draft ads
7. **`call_to_action`** uses field name `key` (not `type`) and `clickthrough_url` (not `url`)
8. Budget amounts must be in **micro-units** (multiply dollar amount by 1,000,000)
9. **`draft_hierarchy_version`** is required when publishing or validating — always fetch the current version from the **draft campaign** immediately before calling publish/validate; never reuse a version captured before child drafts or edits. This field is only populated on draft campaign responses; ad set and ad draft responses return `null`. The version on the campaign increments when any entity in the hierarchy is created or edited
10. **Draft ad set `campaign_id`** must reference the **draft campaign ID**, not a published campaign ID
11. **Draft ad `ad_set_id`** must reference a **draft ad set ID**, not a published ad set ID

## Execution Behavior

- If `auto_execute` is `true`, execute read, create, edit, delete, and validate calls directly after any required planning or asset-selection confirmation.
- If `auto_execute` is `false`, present the curl command to the user and ask for confirmation before executing.
- Never auto-execute `PUBLISH`. Publishing creates live entities and always requires explicit user confirmation immediately before the publish request.
- Always check the `HTTP_STATUS:` line from curl output to determine success or failure before interpreting the response body.
- On error, show the error message from the response body. Never automatically retry POST or PATCH requests.
- **Draft DELETE is safe to retry** — unlike POST/PATCH, DELETE on drafts is idempotent.

## Draft vs Direct Entity Creation

| Aspect | Draft Flow (Preferred) | Direct Flow |
|--------|----------------------|-------------|
| Validation | Batch — validate entire hierarchy at once | Per-entity — errors discovered one at a time |
| Going live | Explicit publish step | Immediate on creation |
| Editing | Free — edit any draft entity before publish | Requires PATCH on live entities |
| Undo | Delete the draft — no cleanup needed | Must archive/pause live entities |
| Use case | New campaigns, major changes | Quick single-entity updates |
