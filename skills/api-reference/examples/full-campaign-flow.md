# Example: Full Campaign Setup Flow

This example shows the complete sequence of API calls to create a campaign, ad set, and ad.

## Step 1: Create Campaign

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
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
