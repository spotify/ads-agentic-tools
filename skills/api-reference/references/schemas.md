# Spotify Ads API v3 — Request/Response Schemas

## Common Types

### Uuid
- Format: UUID v4
- Example: `ce4ff15e-f04d-48b9-9ddf-fb3c85fbd57a`

### EventTime
- Format: ISO 8601 datetime in UTC
- Example: `2025-09-23T04:56:07Z`

### Paging
```json
{
  "page_size": 50,
  "total_results": 116,
  "offset": 0
}
```

### ErrorResponse
```json
{
  "error": {
    "message": "string",
    "code": "string"
  },
  "path": "string",
  "timestamp": "ISO 8601"
}
```

---

## Campaign Schemas

### CampaignResponse
```json
{
  "id": "uuid",
  "name": "string (2-200 chars)",
  "status": "CampaignStatus enum",
  "derived_status": "CampaignDerivedStatus enum",
  "objective": "OptimizationPrefs enum",
  "purchase_order": "string",
  "restricted_ad_category": "string",
  "measurement_partner": "string",
  "created_at": "ISO 8601",
  "updated_at": "ISO 8601",
  "ad_account_id": "uuid",
  "version": "integer"
}
```

### CreateCampaignRequest
Required: `name`, `objective`
```json
{
  "name": "string (2-200 chars)",
  "objective": "REACH | CLICKS | VIDEO_VIEWS | CONVERSIONS | LEAD_GEN | EVEN_IMPRESSION_DELIVERY",
  "purchase_order": "string (optional)",
  "restricted_ad_category": "string (optional)",
  "measurement_partner": "string (optional)"
}
```

### UpdateCampaignRequest
Minimum 1 property required.
```json
{
  "name": "string (2-200 chars, optional)",
  "status": "ACTIVE | PAUSED | ARCHIVED (optional)",
  "restricted_ad_category": "string (optional)"
}
```

---

## Ad Set Schemas

### AdSetResponse
```json
{
  "id": "uuid",
  "name": "string (2-200 chars)",
  "campaign_id": "uuid",
  "status": "AdSetStatus enum",
  "category": "string",
  "cost_model": "CostModel enum",
  "asset_format": "AssetFormat enum",
  "budget": {
    "micro_amount": 50000000,
    "type": "DAILY | LIFETIME"
  },
  "bid_strategy": "MAX_BID | COST_PER_RESULT",
  "bid_micro_amount": 15000000,
  "targets": { "...": "Targets object" },
  "promotion": { "...": "Promotion object" },
  "pacing": "PACING_EVEN | PACING_ACCELERATED",
  "delivery": "ON | OFF",
  "reject_reason": "string",
  "reject_reasons": ["string"],
  "created_at": "ISO 8601",
  "updated_at": "ISO 8601",
  "ad_account_id": "uuid",
  "is_paused": false,
  "version": 1
}
```

### AdSetCreateRequest
Required: `name`, `campaign_id`, `start_time`, `budget`, `asset_format`, `targets`, `bid_strategy`, `category`
```json
{
  "name": "string (2-200 chars)",
  "campaign_id": "uuid",
  "start_time": "ISO 8601",
  "end_time": "ISO 8601 (required if budget type is LIFETIME)",
  "budget": {
    "micro_amount": 50000000,
    "type": "DAILY"
  },
  "asset_format": "AUDIO | VIDEO | IMAGE",
  "category": "string (required, e.g. ADV_1_2 — fetch valid values from GET /ad_categories)",
  "targets": {
    "age_ranges": [{"min": 18, "max": 34}],
    "geo_targets": {"country_code": "US"},
    "artist_ids": ["string"],
    "genre_ids": ["string"],
    "interest_ids": ["string"],
    "platforms": ["ANDROID", "DESKTOP", "IOS"],
    "placements": ["MUSIC"],
    "genders": ["MALE", "FEMALE", "NON_BINARY"]
  },
  "bid_strategy": "MAX_BID",
  "bid_micro_amount": 15000000,
  "pacing": "PACING_EVEN",
  "delivery": "ON",
  "frequency_caps": [{"frequency_unit": "DAY", "frequency_period": 1, "max_impressions": 5}],
  "mobile_app_id": "uuid (optional)"
}
```

**Important schema notes:**
- `bid_strategy` is a **plain string enum** (`MAX_BID`, `COST_PER_RESULT`, `UNSET`), NOT an object.
- `geo_targets` is a **flat object** with a `country_code` string property, NOT an array of objects.
- `platforms` valid values are `ANDROID`, `DESKTOP`, `IOS` — NOT "MOBILE" or "CONNECTED_DEVICE".
- `category` is **required** — use a valid `ADV_X_Y` code from the `GET /ad_categories` endpoint.
- `end_time` is **required** when `budget.type` is `LIFETIME`.
- `placements` inside `targets` is required — typically `["MUSIC"]` or `["PODCAST"]`.

### Targets Object
```json
{
  "age_ranges": [{ "min": 18, "max": 65 }],
  "geo_targets": { "country_code": "US", "city_ids": [], "dma_ids": [], "postal_code_ids": [], "region_ids": [] },
  "artist_ids": ["spotify-artist-id"],
  "genre_ids": ["genre-id"],
  "interest_ids": ["interest-id"],
  "playlist_ids": ["playlist-id"],
  "platforms": ["ANDROID", "DESKTOP", "IOS"],
  "placements": ["MUSIC"],
  "genders": ["MALE", "FEMALE", "NON_BINARY"],
  "language": "en",
  "podcast_episode_topic_ids": ["string"]
}
```

**Important:** `geo_targets` is a single flat object, not an array. The `country_code` field is a string. `language` is a singular string (not an array called `languages`). `platforms` uses `ANDROID`/`IOS` (not `MOBILE`/`CONNECTED_DEVICE`).

---

## Ad Schemas

### AdResponse
```json
{
  "id": "uuid",
  "name": "string (2-200 chars)",
  "ad_set_id": "uuid",
  "advertiser_name": "string",
  "tagline": "string",
  "assets": { "...": "AdResponseAssets" },
  "call_to_action": {
    "type": "string",
    "url": "string"
  },
  "status": "AdStatus enum",
  "delivery": "ON | OFF",
  "reject_reason": "string",
  "reject_reasons": ["string"],
  "placements": ["MUSIC", "PODCAST", "VIDEO"],
  "ad_preview_url": "string URI",
  "third_party_tracking": [{ "type": "string", "url": "string" }],
  "created_at": "ISO 8601",
  "updated_at": "ISO 8601",
  "version": 1
}
```

### CreateAdRequest
Required: `name`, `ad_set_id`, `tagline`, `advertiser_name`, `assets`, `call_to_action`
```json
{
  "name": "string (2-200 chars)",
  "ad_set_id": "uuid",
  "tagline": "string (2-40 chars)",
  "advertiser_name": "string (2-25 chars)",
  "assets": {
    "asset_id": "uuid (required — audio, video, or image creative)",
    "logo_asset_id": "uuid (required — logo image)",
    "companion_asset_id": "uuid (required for AUDIO ads — companion image)",
    "canvas_asset_id": "uuid (optional — 9:16 image or video)"
  },
  "call_to_action": {
    "key": "SHOP_NOW",
    "clickthrough_url": "https://example.com/landing"
  },
  "delivery": "ON",
  "third_party_tracking": [
    { "type": "IMPRESSION", "url": "https://tracker.example.com/imp" }
  ]
}
```

**Important schema notes:**
- `call_to_action` uses field name `key` (NOT `type`) and `clickthrough_url` (NOT `url`).
- `assets.asset_id` and `assets.logo_asset_id` are always required.
- `assets.companion_asset_id` is required for AUDIO format ads.
- Valid `call_to_action.key` values: `SHOP_NOW`, `LEARN_MORE`, `LISTEN_NOW`, `SIGN_UP`, `WATCH_NOW`, `BUY_NOW`, `BOOK_NOW`, `DOWNLOAD`, `GET_INFO`, `ORDER_NOW`, `PRE_SAVE`, `VISIT_SITE`, etc.

### UpdateAdRequest
Minimum 1 property required.
```json
{
  "call_to_action": { "type": "string", "url": "string (optional)" },
  "delivery": "ON | OFF (optional)",
  "status": "APPROVED | ARCHIVED | PENDING (optional)"
}
```

---

## Asset Schemas

### AssetResponse (oneOf: Image, Audio, Video)
```json
{
  "id": "uuid",
  "name": "string",
  "status": "AssetStatus enum",
  "url": "string URI",
  "created_at": "ISO 8601",
  "updated_at": "ISO 8601",
  "file_type": "JPEG | PNG | MP4 | MP3 | WAV | OGG | QUICKTIME",
  "asset_type": "IMAGE | AUDIO | VIDEO"
}
```

### CreateAssetRequest
Required: `asset_type`, `name`
```json
{
  "asset_type": "IMAGE | AUDIO | VIDEO",
  "name": "string (2-120 chars)",
  "asset_subtype": "ADSTUDIO_SUPPLIED_AUDIO | BACKGROUND_MUSIC | USER_UPLOADED_AUDIO (optional)"
}
```

---

## Audience Schemas

### AudienceResponse
```json
{
  "id": "uuid",
  "name": "string",
  "description": "string",
  "type": "CUSTOM | LOOKALIKE",
  "subtype": "string",
  "size": "string (size range)",
  "status": "AudienceStatus enum",
  "created_at": "ISO 8601",
  "updated_at": "ISO 8601",
  "sources": [{ "...": "AudienceSource" }],
  "seed_audience_id": "uuid (for lookalike)",
  "lookalike_audience_ids": ["uuid"],
  "lookback_days": 30,
  "campaign_ids": ["uuid"],
  "ad_set_ids": ["uuid"]
}
```

---

## Report Schemas

### AggregateReportResponse

**Query parameter notes:** The metrics parameter is called `fields` (NOT `report_fields`). Array values must use repeated parameter format (`fields=IMPRESSIONS&fields=SPEND`), NOT comma-separated. Valid field values: `IMPRESSIONS`, `SPEND`, `CLICKS`, `REACH`, `FREQUENCY`, `LISTENERS`, `NEW_LISTENERS`, `STREAMS`, `COMPLETES`, `COMPLETION_RATE`, `STARTS`, `FIRST_QUARTILES`, `MIDPOINTS`, `THIRD_QUARTILES`, `VIDEO_VIEWS`, `CTR`, `OFF_SPOTIFY_IMPRESSIONS`.

```json
{
  "continuation_token": "string (base64) | null",
  "report_start": "ISO 8601",
  "report_end": "ISO 8601",
  "granularity": "HOUR | DAY | LIFETIME",
  "rows": [{
    "entity_type": "CAMPAIGN | AD_SET | AD | AD_ACCOUNT",
    "entity_id": "uuid",
    "entity_name": "string",
    "entity_status": "string",
    "start_time": "ISO 8601",
    "end_time": "ISO 8601",
    "stats": [{
      "field_type": "IMPRESSIONS | SPEND | CLICKS | REACH | ...",
      "field_value": "float (e.g., 15234.0, 0.0)"
    }]
  }],
  "warnings": ["string"]
}
```

**Notes:**
- `field_value` is a **float**, not a string. Zero values appear as `0.0`.
- `SPEND` values are in micro-amounts — divide by 1,000,000 for dollars.
- Do NOT use async report metric names (`AD_COMPLETES`, `CPM`, `IMPRESSIONS_ON_SPOTIFY`) — use `COMPLETES`, `IMPRESSIONS` instead.

### CreateAsyncReportRequest
Required: `name`, `granularity`, `dimensions`, `metrics`
```json
{
  "name": "string (2-120 chars)",
  "granularity": "DAY | LIFETIME",
  "dimensions": [
    "AD_ACCOUNT_NAME", "CAMPAIGN_NAME", "AD_SET_NAME", "AD_NAME",
    "CAMPAIGN_STATUS", "AD_SET_STATUS", "AD_SET_BUDGET", "AD_SET_COST_MODEL"
  ],
  "metrics": [
    "IMPRESSIONS_ON_SPOTIFY", "IMPRESSIONS_OFF_SPOTIFY", "SPEND",
    "CLICKS", "REACH", "FREQUENCY", "LISTENERS", "NEW_LISTENERS",
    "STREAMS", "AD_COMPLETES", "CTR", "CPM", "COMPLETION_RATE"
  ],
  "statuses": ["ACTIVE"],
  "campaign_ids": ["uuid (optional)"],
  "report_start": "ISO 8601 (required if DAY)",
  "report_end": "ISO 8601 (optional)"
}
```

### AudienceInsightResponse
```json
{
  "granularity": "LIFETIME",
  "entity": "CAMPAIGN | AD_SET",
  "insight": "GENDER | PLATFORM | LOCATION | ARTIST | GENRE",
  "rows": [{
    "id": "uuid",
    "name": "string",
    "status": "string",
    "insight_value": "string",
    "stats": [{ "field_type": "string", "field_value": "string" }]
  }]
}
```

---

## Estimate Schemas

### AudienceEstimateRequest
Required: `ad_account_id`, `start_date`, `asset_format`, `objective`, `bid_strategy`, `bid_micro_amount`, `budget`, `targets`

**Important:** `budget` here requires a `currency` field (e.g. "USD") in addition to `micro_amount` and `type`. This differs from the ad set budget which does not require `currency`.

```json
{
  "ad_account_id": "uuid",
  "start_date": "ISO 8601",
  "end_date": "ISO 8601 (optional)",
  "asset_format": "AUDIO | VIDEO | IMAGE",
  "objective": "REACH | CLICKS | VIDEO_VIEWS | CONVERSIONS | LEAD_GEN | EVEN_IMPRESSION_DELIVERY",
  "bid_strategy": "MAX_BID | COST_PER_RESULT | UNSET",
  "bid_micro_amount": 15000000,
  "budget": {
    "micro_amount": 5000000,
    "type": "DAILY | LIFETIME",
    "currency": "USD"
  },
  "frequency_caps": [{"frequency_unit": "WEEK", "frequency_period": 1, "max_impressions": 2}],
  "targets": { "...": "Targets object (same as ad set)" },
  "category": "ADV_X_Y (optional)"
}
```

### AudienceEstimateResponse
```json
{
  "audience_forecast": [
    {
      "forecast_type": "DAILY | WEEKLY | MONTHLY | LIFETIME",
      "estimated_reach_min": 300,
      "estimated_reach_max": 700,
      "estimated_impressions_min": 300,
      "estimated_impressions_max": 700,
      "estimated_frequency_min": 1.0,
      "estimated_frequency_max": 2.3,
      "estimated_cpm_min": 6076000,
      "estimated_cpm_max": 14177000,
      "projected_unique_users": 493,
      "raw_unique_users": 421697,
      "recommendation_results": {
        "show_recommendation": true,
        "billable_events": 740,
        "unique_users": 739,
        "budget": { "micro_amount": 7500094, "currency": "USD" }
      }
    }
  ],
  "bid_suggestion": {
    "bid_estimate_min": 5878000,
    "bid_estimate_max": 7053000,
    "cost_model": "CPM",
    "currency": "USD"
  },
  "likely_to_deliver_budget": true
}
```

**Notes:**
- DAILY budgets return up to 3 forecast entries (DAILY, WEEKLY, MONTHLY). LIFETIME budgets return 1 entry (LIFETIME).
- `raw_unique_users` is the exact audience count from the past 7 days without adjustments.
- `projected_unique_users` is adjusted for frequency caps, budget, and schedule.
- All monetary values are in micro-units. Divide by 1,000,000 for dollars.

### BidEstimateRequest
Required: `asset_format`, `objective`, `bid_strategy`, `currency`, `targets`
```json
{
  "asset_format": "AUDIO | VIDEO | IMAGE",
  "objective": "REACH | CLICKS | VIDEO_VIEWS | CONVERSIONS | LEAD_GEN | EVEN_IMPRESSION_DELIVERY",
  "bid_strategy": "MAX_BID | COST_PER_RESULT | UNSET",
  "currency": "USD",
  "targets": { "...": "Targets object (same as ad set)" },
  "frequency_caps": [{"frequency_unit": "WEEK", "frequency_period": 1, "max_impressions": 2}],
  "category": "ADV_X_Y (optional)"
}
```

### BidEstimateResponse
```json
{
  "bid_estimate_min": 8014566,
  "bid_estimate_max": 9795581,
  "cost_model": "CPM",
  "currency": "USD"
}
```

Bid amounts are in micro-units. Divide by 1,000,000 for dollar values.
