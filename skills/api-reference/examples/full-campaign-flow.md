# Example: Full Campaign Setup Flow

This example shows the complete sequence of API calls to create a campaign, ad set, and ad.

## Step 1: Create Campaign

```bash
curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Summer Sale 2025",
    "objective": "REACH"
  }' \
  "https://api-partner.spotify.com/ads-sandbox/v3/ad_accounts/$AD_ACCOUNT_ID/campaigns"
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
curl -s -X POST \
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
    "targets": {
      "age_ranges": [{"min": 18, "max": 34}],
      "geo_targets": [{"country_code": "US"}],
      "genders": ["MALE", "FEMALE", "NON_BINARY"],
      "platforms": ["MOBILE", "DESKTOP"]
    },
    "bid_strategy": {
      "type": "LOWEST_COST"
    },
    "pacing": "PACING_EVEN",
    "delivery": "ON"
  }' \
  "https://api-partner.spotify.com/ads-sandbox/v3/ad_accounts/$AD_ACCOUNT_ID/ad_sets"
```

**Expected Response (201):**
```json
{
  "id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
  "name": "Summer Sale - Audio US 18-34",
  "campaign_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "status": "PENDING",
  "asset_format": "AUDIO",
  "budget": { "micro_amount": 50000000, "type": "DAILY" },
  "targets": { "...": "..." },
  "created_at": "2025-06-01T12:05:00Z"
}
```

Save the `id` for the ad.

## Step 3: Create Ad

Uses the `ad_set_id` from Step 2.

```bash
curl -s -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Summer Sale - 30s Audio Spot",
    "ad_set_id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
    "tagline": "Summer deals up to 50% off",
    "advertiser_name": "My Brand",
    "assets": {},
    "call_to_action": {
      "type": "SHOP_NOW",
      "url": "https://mybrand.com/summer-sale"
    },
    "delivery": "ON",
    "placements": ["MUSIC"]
  }' \
  "https://api-partner.spotify.com/ads-sandbox/v3/ad_accounts/$AD_ACCOUNT_ID/ads"
```

**Expected Response (201):**
```json
{
  "id": "c3d4e5f6-a7b8-9012-cdef-123456789012",
  "name": "Summer Sale - 30s Audio Spot",
  "ad_set_id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
  "status": "PENDING_APPROVAL",
  "delivery": "ON",
  "placements": ["MUSIC"],
  "created_at": "2025-06-01T12:10:00Z"
}
```

## Common Pitfalls

- Forgetting to convert dollar amounts to micro-amounts (multiply by 1,000,000)
- Missing required fields on ad set creation (all 6 required fields must be present)
- Using a `campaign_id` that doesn't belong to the same `ad_account_id`
- Setting `end_time` before `start_time`
