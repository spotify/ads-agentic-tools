# Example: Full Campaign Setup Flow

**Note:** All curl examples below assume `SDK_HEADER="X-Spotify-Ads-Sdk: $SDK_PRODUCT/$PLUGIN_VERSION"`, where `SDK_PRODUCT` is `codex-plugin` on Codex, `claude-code-plugin` on Claude, and `gemini-cli-extension` on Gemini.

This example shows the complete sequence of API calls to create a campaign, ad set, and ad.

**Recommended:** Use the draft flow (see [Draft Campaign Flow](#draft-campaign-flow-recommended) at the end) for new campaigns. It validates the entire hierarchy before going live.

## Direct Flow (Legacy)

## Step 1: Create Campaign

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Summer Sale 2025",
    "objective": "REACH"
  }' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/campaigns"
```

**Expected Response (201):**
```json
{
  "id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "name": "Summer Sale 2025",
  "status": "ACTIVE",
  "objective": "REACH",
  "created_at": "2025-06-01T12:00:00Z",
  "updated_at": "2025-06-01T12:00:00Z",
  "ad_account_id": "your-ad-account-id"
}
```

Save the `id` from the response — it's needed for the ad set.

## Step 2: Create Ad Set

Uses the `campaign_id` from Step 1. Note: budget `micro_amount` is in micro-units ($50 = 50000000).

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Summer Sale - Audio US 18-34",
    "campaign_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "start_time": "2025-06-15T00:00:00Z",
    "end_time": "2025-07-15T23:59:59Z",
    "budget": {
      "micro_amount": 50000000,
      "type": "DAILY"
    },
    "asset_format": "AUDIO",
    "category": "ADV_1_2",
    "targets": {
      "age_ranges": [{"min": 18, "max": 34}],
      "geo_targets": {"country_code": "US"},
      "platforms": ["ANDROID", "DESKTOP", "IOS"],
      "placements": ["MUSIC"]
    },
    "bid_strategy": "MAX_BID",
    "bid_micro_amount": 15000000,
    "pacing": "PACING_EVEN",
    "delivery": "ON"
  }' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/ad_sets"
```

**Expected Response (201):**
```json
{
  "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
  "name": "Summer Sale - Audio US 18-34",
  "campaign_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "status": "PENDING_APPROVAL",
  "asset_format": "AUDIO",
  "category": "ADV_1_2",
  "budget": { "micro_amount": 50000000, "type": "DAILY", "currency": "USD" },
  "bid_strategy": "MAX_BID",
  "bid_micro_amount": 15000000,
  "targets": {
    "age_ranges": [{"min": 18, "max": 34}],
    "geo_targets": {"country_code": "US"},
    "platforms": ["ANDROID", "DESKTOP", "IOS"],
    "placements": ["MUSIC"]
  },
  "created_at": "2025-06-01T12:05:00Z"
}
```

Save the `id` for the ad.

## Step 3: Create Ad

Uses the `ad_set_id` from Step 2.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Summer Sale - 30s Audio Spot",
    "ad_set_id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
    "tagline": "Summer deals up to 50% off",
    "advertiser_name": "My Brand",
    "assets": {
      "asset_id": "audio-asset-uuid",
      "logo_asset_id": "logo-image-uuid",
      "companion_asset_id": "companion-image-uuid"
    },
    "call_to_action": {
      "key": "SHOP_NOW",
      "clickthrough_url": "https://mybrand.com/summer-sale"
    },
    "delivery": "ON"
  }' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/ads"
```

**Expected Response (201):**
```json
{
  "id": "c3d4e5f6-a7b8-9012-cdef-123456789012",
  "name": "Summer Sale - 30s Audio Spot",
  "ad_set_id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
  "status": "PENDING_APPROVAL",
  "delivery": "ON",
  "call_to_action": {
    "key": "SHOP_NOW",
    "text": "Shop now",
    "clickthrough_url": "https://mybrand.com/summer-sale"
  },
  "assets": {
    "asset_id": "audio-asset-uuid",
    "logo_asset_id": "logo-image-uuid",
    "companion_asset_id": "companion-image-uuid"
  },
  "created_at": "2025-06-01T12:10:00Z"
}
```

## Critical Schema Pitfalls

These are non-obvious requirements discovered through real API testing:

### Ad Set Creation
- **`category` is required** — Must be a valid `ADV_X_Y` code. Fetch valid values from `GET /ad_categories`.
- **`bid_strategy` is a plain string**, NOT an object. Use `"bid_strategy": "MAX_BID"`, not `"bid_strategy": {"type": "MAX_BID"}`.
- **`geo_targets` is a flat object**, NOT an array. Use `{"country_code": "US"}`, not `[{"country_code": "US"}]`.
- **`platforms` valid values are `ANDROID`, `DESKTOP`, `IOS`** — NOT "MOBILE" or "CONNECTED_DEVICE".
- **`placements`** inside `targets` is required — typically `["MUSIC"]` or `["PODCAST"]`.
- **`end_time` is required** when `budget.type` is `LIFETIME`.
- **Min audience thresholds** apply — VIDEO format requires broader targeting than AUDIO. If you hit this error, try expanding the age range.
- Omitting `bid_micro_amount` when using `bid_strategy: MAX_BID` will cause an error.

### Ad Creation
- **`call_to_action` uses `key`** (not `type`) and **`clickthrough_url`** (not `url`).
- **`assets.companion_asset_id` is required** for AUDIO format ad sets.
- **`assets.asset_id` and `assets.logo_asset_id` are always required**.
- `tagline` max length is 40 chars; `advertiser_name` max length is 25 chars.

### General
- All budgets and bids use **micro-amounts** — multiply dollar values by 1,000,000.
- Using a `campaign_id` that doesn't belong to the same `ad_account_id` will fail.
- Setting `end_time` before `start_time` will fail.

---

## Draft Campaign Flow (Recommended)

The draft flow creates staging entities, validates everything at once, then publishes. Same data, safer workflow.

### Step 1: Create Draft Campaign

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Summer Sale 2025",
    "objective": "REACH"
  }' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns"
```

**Expected Response (200):**
```json
{
  "id": "d1e2f3a4-b5c6-7890-abcd-ef1234567890",
  "name": "Summer Sale 2025",
  "objective": "REACH",
  "draft_hierarchy_version": 1,
  "created_at": "2025-06-01T12:00:00Z"
}
```

Save `id` and `draft_hierarchy_version`.

### Step 2: Create Draft Ad Set

Uses the draft `campaign_id` from Step 1.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "campaign_id": "d1e2f3a4-b5c6-7890-abcd-ef1234567890",
    "name": "Summer Sale - Audio US 18-34",
    "start_time": "2025-06-15T00:00:00Z",
    "end_time": "2025-07-15T23:59:59Z",
    "budget": {
      "micro_amount": 50000000,
      "type": "DAILY"
    },
    "asset_format": "AUDIO",
    "category": "ADV_1_2",
    "targets": {
      "age_ranges": [{"min": 18, "max": 34}],
      "geo_targets": {"country_code": "US"},
      "platforms": ["ANDROID", "DESKTOP", "IOS"],
      "placements": ["MUSIC"]
    },
    "bid_strategy": "MAX_BID",
    "bid_micro_amount": 15000000
  }' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/drafts/ad_sets"
```

### Step 3: Create Draft Ad

Uses the draft `ad_set_id` from Step 2.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "ad_set_id": "e2f3a4b5-c6d7-8901-bcde-f12345678901",
    "name": "Summer Sale - 30s Audio Spot",
    "tagline": "Summer deals up to 50% off",
    "advertiser_name": "My Brand",
    "assets": {
      "asset_id": "audio-asset-uuid",
      "logo_asset_id": "logo-image-uuid",
      "companion_asset_id": "companion-image-uuid"
    },
    "call_to_action": {
      "key": "SHOP_NOW",
      "clickthrough_url": "https://mybrand.com/summer-sale"
    }
  }' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/drafts/ads"
```

### Step 4: Validate the Draft Hierarchy

Dry-run publish to check for errors across the entire hierarchy. First fetch the draft campaign to get the current `draft_hierarchy_version`; do not reuse the version returned before child draft ad sets or ads were created.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "$SDK_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/d1e2f3a4-b5c6-7890-abcd-ef1234567890"
```

Set `CURRENT_DRAFT_HIERARCHY_VERSION` from the `draft_hierarchy_version` field in that response.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d "{\"action\":\"VALIDATE\",\"draft_hierarchy_version\":$CURRENT_DRAFT_HIERARCHY_VERSION}" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/d1e2f3a4-b5c6-7890-abcd-ef1234567890"
```

**Success (200, no errors; no live entities are created):**
```json
{
  "validation_errors": null
}
```

**Validation errors (400, with errors):**
```json
{
  "validation_errors": [
    {
      "validation_entity_type": "AD_SET",
      "validation_entity_id": "e2f3a4b5-c6d7-8901-bcde-f12345678901",
      "message": "Ad set targeting is required"
    },
    {
      "validation_entity_type": "AD",
      "validation_entity_id": "f3a4b5c6-d7e8-9012-cdef-123456789012",
      "message": "Missing companion_asset_id for AUDIO format"
    }
  ]
}
```

Fix errors with PATCH on the draft entities, then re-validate.

### Step 5: Publish

Once validation passes, publish to create live entities. Fetch the draft campaign again immediately before publishing. If the version has changed since validation, re-run validation with the new version before publishing.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "$SDK_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/d1e2f3a4-b5c6-7890-abcd-ef1234567890"
```

Set `CURRENT_DRAFT_HIERARCHY_VERSION` from this latest response.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d "{\"action\":\"PUBLISH\",\"draft_hierarchy_version\":$CURRENT_DRAFT_HIERARCHY_VERSION}" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/drafts/campaigns/d1e2f3a4-b5c6-7890-abcd-ef1234567890"
```

**Expected Response (200):**
```json
{
  "campaign": {
    "id": "published-campaign-uuid",
    "name": "Summer Sale 2025",
    "status": "ACTIVE",
    "objective": "REACH"
  },
  "validation_errors": null
}
```

### Draft Schema Notes

All the same schema pitfalls from the direct flow apply to drafts (bid_strategy is a string, geo_targets is flat, etc.). Additional draft-specific notes:

- **`draft_hierarchy_version`** is read-only — populated on draft campaign responses. Draft ad set and draft ad responses return `null` for this field. Must be passed when publishing or validating. It increments whenever any entity in the hierarchy is edited, so always fetch the draft campaign immediately before validate/publish.
- **Draft entities can be truly deleted** (DELETE returns 204) — unlike live entities which can only be archived.
- **Draft `campaign_id` and `ad_set_id`** must reference other draft entity IDs, not published entity IDs.
