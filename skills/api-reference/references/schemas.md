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
  "bid_strategy": { "...": "BidStrategyResponse" },
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
Required: `name`, `campaign_id`, `start_time`, `budget`, `asset_format`, `targets`, `bid_strategy`
```json
{
  "name": "string (2-200 chars)",
  "campaign_id": "uuid",
  "start_time": "ISO 8601",
  "end_time": "ISO 8601 (optional)",
  "budget": {
    "micro_amount": 50000000,
    "type": "DAILY"
  },
  "asset_format": "AUDIO | VIDEO | IMAGE | AUDIO_PODCAST",
  "targets": {
    "age_ranges": [{"min": 18, "max": 34}],
    "geo_targets": [{"country_code": "US"}],
    "artist_ids": ["string"],
    "genre_ids": ["string"],
    "interest_ids": ["string"],
    "platforms": ["DESKTOP", "MOBILE"],
    "genders": ["MALE", "FEMALE", "NON_BINARY"]
  },
  "bid_strategy": { "type": "string" },
  "bid_micro_amount": 15000000,
  "pacing": "PACING_EVEN",
  "delivery": "ON",
  "frequency_caps": { "...": "optional" },
  "mobile_app_id": "uuid (optional)"
}
```

### Targets Object
```json
{
  "age_ranges": [{ "min": 18, "max": 65 }],
  "geo_targets": [{ "country_code": "US", "region": "CA" }],
  "artist_ids": ["spotify-artist-id"],
  "genre_ids": ["genre-id"],
  "interest_ids": ["interest-id"],
  "playlist_ids": ["playlist-id"],
  "platforms": ["DESKTOP", "MOBILE", "CONNECTED_DEVICE"],
  "genders": ["MALE", "FEMALE", "NON_BINARY"],
  "languages": ["en", "es"],
  "moment_targets": ["string"],
  "episode_topic_ids": ["string"]
}
```

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
Required: `name`, `assets`
Also needed: `tagline`, `advertiser_name`, `ad_set_id`, `call_to_action`
```json
{
  "name": "string (2-200 chars)",
  "ad_set_id": "uuid",
  "tagline": "string",
  "advertiser_name": "string",
  "assets": { "...": "AdRequestAssets" },
  "call_to_action": {
    "type": "LEARN_MORE | SIGN_UP | SHOP_NOW | LISTEN_NOW | WATCH_NOW | ...",
    "url": "https://example.com/landing"
  },
  "delivery": "ON",
  "placements": ["MUSIC", "PODCAST"],
  "asset_format": "AUDIO",
  "asset_uri": "string (optional)",
  "third_party_tracking": [
    { "type": "IMPRESSION", "url": "https://tracker.example.com/imp" }
  ]
}
```

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
```json
{
  "continuation_token": "string (base64)",
  "report_start": "ISO 8601",
  "report_end": "ISO 8601",
  "granularity": "HOUR | DAY | LIFETIME",
  "rows": [{
    "entity_type": "CAMPAIGN | AD_SET | AD",
    "entity_id": "uuid",
    "entity_name": "string",
    "entity_status": "string",
    "start_time": "ISO 8601",
    "end_time": "ISO 8601",
    "stats": [{
      "field_type": "IMPRESSIONS | SPEND | CLICKS | REACH | ...",
      "field_value": "string (numeric)"
    }]
  }],
  "warnings": ["string"]
}
```

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
