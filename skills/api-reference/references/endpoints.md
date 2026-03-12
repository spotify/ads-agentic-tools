# Spotify Ads API v3 — Endpoint Reference

## Campaigns

### POST /ad_accounts/{ad_account_id}/campaigns
Create a new campaign.

**Path Parameters:**
- `ad_account_id` (uuid, required) — Ad account identifier

**Request Body:** `CreateCampaignRequest`
- `name` (string, 2-200 chars, required)
- `objective` (string, required) — One of: REACH, EVEN_IMPRESSION_DELIVERY, CLICKS, VIDEO_VIEWS, CONVERSIONS, LEAD_GEN
- `purchase_order` (string, optional)
- `restricted_ad_category` (string, optional)
- `measurement_partner` (string, optional)

**Response:** 201 — `CampaignResponse`

### GET /ad_accounts/{ad_account_id}/campaigns
List campaigns for the ad account.

**Path Parameters:**
- `ad_account_id` (uuid, required)

**Query Parameters:**
- `campaign_ids` (array of uuid) — Filter by specific campaign IDs
- `name` (string) — Filter by name (case-insensitive)
- `statuses` (array) — Filter by status: ACTIVE, PAUSED, ARCHIVED, etc.
- `campaign_sort_field` (string) — Sort by: CREATED_AT, UPDATED_AT, NAME
- `sort_direction` (string) — ASC or DESC (default: DESC)
- `limit` (integer, 1-50, default 50)
- `offset` (integer, default 0)

**Response:** 200 — `CampaignsListResponse`
```json
{
  "paging": { "page_size": 50, "total_results": 10, "offset": 0 },
  "campaigns": [{ "id": "...", "name": "...", "status": "...", ... }]
}
```

### GET /ad_accounts/{ad_account_id}/campaigns/{campaign_id}
Get a specific campaign by ID.

**Path Parameters:**
- `ad_account_id` (uuid, required)
- `campaign_id` (uuid, required)

**Response:** 200 — `CampaignResponse`

### PATCH /ad_accounts/{ad_account_id}/campaigns/{campaign_id}
Update a campaign. Minimum 1 property required.

**Path Parameters:**
- `ad_account_id` (uuid, required)
- `campaign_id` (uuid, required)

**Request Body:** `UpdateCampaignRequest`
- `name` (string, 2-200 chars, optional)
- `status` (string, optional) — ACTIVE, PAUSED, ARCHIVED
- `restricted_ad_category` (string, optional)

**Response:** 200 — `CampaignResponse`

---

## Ad Sets

### POST /ad_accounts/{ad_account_id}/ad_sets
Create a new ad set within a campaign.

**Path Parameters:**
- `ad_account_id` (uuid, required)

**Request Body:** `AdSetCreateRequest`
- `name` (string, 2-200 chars, required)
- `campaign_id` (uuid, required)
- `start_time` (ISO 8601 datetime, required)
- `end_time` (ISO 8601 datetime, **required if budget type is LIFETIME**)
- `budget` (object, required):
  - `micro_amount` (int64, required) — Budget in micro-units ($1 = 1000000)
  - `type` (string, required) — DAILY or LIFETIME
- `asset_format` (string, required) — AUDIO, VIDEO, or IMAGE
- `category` (string, **required**) — Ad category code (e.g. `ADV_1_2`). Fetch valid values from `GET /ad_categories`
- `targets` (object, required) — See Targeting section. **Note:** `geo_targets` is a flat object `{"country_code":"US"}`, NOT an array. `platforms` valid values are `ANDROID`, `DESKTOP`, `IOS`.
- `bid_strategy` (string, required) — Plain string enum: `MAX_BID`, `COST_PER_RESULT`, or `UNSET`. **Not an object.**
- `bid_micro_amount` (int64, required with MAX_BID) — Bid cap in micro-units. With MAX_BID, this is the maximum CPM. Example: $15 bid cap = `15000000`
- `promotion` (object, optional) — Promotion configuration
- `frequency_caps` (array, optional) — Array of `{frequency_unit, frequency_period, max_impressions}` objects
- `pacing` (string, optional) — PACING_EVEN or PACING_ACCELERATED
- `delivery` (string, optional) — ON or OFF
- `mobile_app_id` (uuid, optional) — For app install campaigns

**Response:** 201 — `AdSetResponse`

### GET /ad_accounts/{ad_account_id}/ad_sets/{ad_set_id}
Get a specific ad set by ID.

**Path Parameters:**
- `ad_account_id` (uuid, required)
- `ad_set_id` (uuid, required)

**Response:** 200 — `AdSetResponse`

### GET /ad_accounts/{ad_account_id}/ad_sets
List ad sets for the ad account.

**Path Parameters:**
- `ad_account_id` (uuid, required)

**Query Parameters:**
- `campaign_ids` (array of uuid) — Filter by campaign
- `ad_set_ids` (array of uuid) — Filter by specific ad set IDs
- `name` (string) — Filter by name
- `statuses` (array) — Filter by status
- `asset_formats` (array) — Filter by format
- `sort_direction` (string) — ASC or DESC
- `ad_set_sort_field` (string) — CREATED_AT, UPDATED_AT, NAME
- `limit` (integer, 1-50, default 50)
- `offset` (integer, default 0)

**Response:** 200 — `AdSetsListResponse`

### PATCH /ad_accounts/{ad_account_id}/ad_sets/{ad_set_id}
Update an ad set. Minimum 1 property required.

**Path Parameters:**
- `ad_account_id` (uuid, required)
- `ad_set_id` (uuid, required)

**Request Body:** `UpdateAdSetRequest` — Same fields as create, all optional. Minimum 1 required.

**Response:** 200 — `AdSetResponse`

---

## Ads

### POST /ad_accounts/{ad_account_id}/ads
Create a new ad within an ad set.

**Path Parameters:**
- `ad_account_id` (uuid, required)

**Request Body:** `CreateAdRequest`
- `name` (string, 2-200 chars, required)
- `ad_set_id` (uuid, required)
- `tagline` (string, 2-40 chars, required) — Ad tagline/headline
- `advertiser_name` (string, 2-25 chars, required)
- `assets` (object, required) — Asset references:
  - `asset_id` (uuid, required) — Audio, video, or image creative asset
  - `logo_asset_id` (uuid, required) — Logo image asset
  - `companion_asset_id` (uuid, required for AUDIO) — Companion image asset
  - `canvas_asset_id` (uuid, optional) — 9:16 image or video asset
- `call_to_action` (object, required) — CTA configuration. **Uses field `key` (not `type`) and `clickthrough_url` (not `url`)**:
  - `key` (string, required) — e.g. `SHOP_NOW`, `LEARN_MORE`, `LISTEN_NOW`
  - `clickthrough_url` (string, required) — Landing page URL
  - `language` (string, optional, default `ENGLISH`)
- `delivery` (string, optional) — ON or OFF
- `third_party_tracking` (array, optional, max 11) — Third-party tracking URLs

**Response:** 201 — `AdResponse`

### GET /ad_accounts/{ad_account_id}/ads
List ads for the ad account.

**Path Parameters:**
- `ad_account_id` (uuid, required)

**Query Parameters:**
- `ad_set_ids` (array of uuid) — Filter by ad set
- `campaign_ids` (array of uuid) — Filter by campaign
- `ad_ids` (array of uuid) — Filter by specific ad IDs
- `asset_ids` (array of uuid) — Filter by asset
- `name` (string) — Filter by name
- `statuses` (array) — Filter by status
- `ad_fields` (string) — Specific fields to return
- `sort_direction` (string) — ASC or DESC
- `ad_sort_field` (string) — CREATED_AT, UPDATED_AT, etc.
- `limit` (integer, 1-50, default 50)
- `offset` (integer, default 0)

**Response:** 200 — `AdsListResponse`

### GET /ad_accounts/{ad_account_id}/ads/{ad_id}
Get a specific ad by ID.

**Response:** 200 — `AdResponse`

### PATCH /ad_accounts/{ad_account_id}/ads/{ad_id}
Update an ad.

**Request Body:** `UpdateAdRequest`
- `call_to_action` (object, optional)
- `delivery` (string, optional) — ON or OFF
- `status` (string, optional) — APPROVED, ARCHIVED, PENDING

**Response:** 200 — `AdResponse`

---

## Assets

### POST /ad_accounts/{ad_account_id}/assets
Create an asset (image, audio, or video).

**Request Body:** `CreateAssetRequest`
- `asset_type` (string, required) — IMAGE, AUDIO, or VIDEO
- `name` (string, 2-120 chars, required)
- `asset_subtype` (string, optional) — For audio: ADSTUDIO_SUPPLIED_AUDIO, BACKGROUND_MUSIC, USER_UPLOADED_AUDIO

**Response:** 200 — `AssetResponse`

### GET /ad_accounts/{ad_account_id}/assets
List assets for the ad account.

**Query Parameters:**
- `asset_ids` (array of uuid) — Filter by IDs
- `asset_types` (array) — IMAGE, AUDIO, VIDEO
- `asset_statuses` (array) — Filter by status
- `name` (string) — Filter by name
- `sort_direction` (string) — ASC or DESC
- `sort_field` (string) — Sort field
- `limit` (integer, 1-50, default 50)
- `offset` (integer, default 0)

**Response:** 200 — `AssetsResponse`

### GET /ad_accounts/{ad_account_id}/assets/{asset_id}
Get a specific asset.

**Response:** 200 — `AssetResponse`

### PATCH /ad_accounts/{ad_account_id}/assets/{asset_id}
Update an asset.

**Request Body:** `UpdateAssetRequest`
- `asset_type` (string, required)
- `name` (string, 2-120 chars, optional)

**Response:** 200 — `AssetResponse`

### PATCH /ad_accounts/{ad_account_id}/assets
Bulk archive or unarchive assets.

**Request Body:** `BulkUpdateAssetsRequest`
- `action` (string, required) — ARCHIVE or UNARCHIVE
- `ids` (array of uuid, required, min 1)

**Response:** 200 — `BulkUpdateAssetsResponse`

---

## Audiences

### POST /ad_accounts/{ad_account_id}/audiences
Create a new audience. Uses discriminated union based on `audience_type`.

**Request Body:** One of:
- `CreateCustomAudienceRequest` (audience_type: CUSTOM)
- `CreateLookalikeAudienceRequest` (audience_type: LOOKALIKE)

**Response:** 201 — `AudienceResponse`

### GET /ad_accounts/{ad_account_id}/audiences
List audiences for the ad account.

**Query Parameters:**
- `audience_ids` (array of uuid)
- `audience_types` (array) — CUSTOM, LOOKALIKE
- `q` (string) — Case-insensitive search
- `sort_direction` (string) — ASC or DESC
- `audience_sort_field` (string) — CREATED_AT, UPDATED_AT, NAME
- `limit` (integer, 1-50, default 50)
- `offset` (integer, default 0)

**Response:** 200 — `AudiencesListResponse`

### DELETE /ad_accounts/{ad_account_id}/audiences/{audience_id}
Delete an audience.

**Response:** 204 No Content

---

## Reports

### GET /ad_accounts/{ad_account_id}/aggregate_reports
Get aggregated campaign metrics.

**Query Parameters:**
- `entity_type` (string, required) — Entity to report on: `CAMPAIGN`, `AD_SET`, `AD`, or `AD_ACCOUNT`
- `fields` (array, required) — Metrics to include. **Parameter name is `fields`, NOT `report_fields`.** Must use **repeated parameter format** (`fields=IMPRESSIONS&fields=SPEND`), NOT comma-separated.
  Valid values: `IMPRESSIONS`, `SPEND`, `CLICKS`, `REACH`, `FREQUENCY`, `LISTENERS`, `NEW_LISTENERS`, `STREAMS`, `COMPLETES`, `COMPLETION_RATE`, `STARTS`, `FIRST_QUARTILES`, `MIDPOINTS`, `THIRD_QUARTILES`, `VIDEO_VIEWS`, `CTR`, `OFF_SPOTIFY_IMPRESSIONS`
  Note: `CTR` and `CPM` from async reports are NOT valid here. Use `COMPLETES` (not `AD_COMPLETES`).
- `granularity` (string) — `HOUR`, `DAY`, or `LIFETIME` (default: `LIFETIME`)
- `report_start` (ISO 8601 datetime, optional for LIFETIME)
- `report_end` (ISO 8601 datetime, optional for LIFETIME)
- `entity_ids` (array of uuid) — Filter to specific entities (repeated format)
- `entity_ids_type` (string) — Type of IDs in entity_ids: `CAMPAIGN`, `AD_SET`, `AD`
- `entity_status_type` (string) — Filter by status
- `include_parent_entity` (boolean) — Include parent entity info for AD_SET/AD
- `continuation_token` (string) — For pagination
- `limit` (integer, 1-50)

**Granularity constraints:**
- `LIFETIME` / `DAY`: date range must be within 90 days
- `HOUR`: date range must be within the last 2 weeks

**Response:** 200 — `AggregateReportResponse`
```json
{
  "continuation_token": null,
  "report_start": "2025-01-01T00:00:00Z",
  "report_end": "2025-01-31T23:59:59Z",
  "granularity": "LIFETIME",
  "rows": [{
    "entity_type": "AD_SET",
    "entity_id": "...",
    "entity_name": "...",
    "start_time": "...",
    "end_time": "...",
    "stats": [{ "field_type": "IMPRESSIONS", "field_value": 15234.0 }]
  }]
}
```

Note: `field_value` is a **float** (e.g., `15234.0`, `0.0`), not a string. `SPEND` values are in micro-amounts — divide by 1,000,000 for dollar values.

### GET /ad_accounts/{ad_account_id}/insight_reports
Get audience insight breakdowns.

**Query Parameters:**
- `insight_dimension` (string) — GENDER, PLATFORM, LOCATION, ARTIST, GENRE
- `fields` (array) — **Uses `fields`, NOT `report_fields`.** Repeated parameter format.
- `entity_ids` (array of uuid)

**Response:** 200 — `AudienceInsightResponse`

### POST /ad_accounts/{ad_account_id}/async_reports
Create an asynchronous CSV report.

**Request Body:** `CreateAsyncReportRequest`
- `name` (string, 2-120 chars, required)
- `granularity` (string, required) — DAY or LIFETIME
- `dimensions` (array, required) — AD_ACCOUNT_NAME, CAMPAIGN_NAME, AD_SET_NAME, AD_NAME, etc.
- `metrics` (array, required) — IMPRESSIONS_ON_SPOTIFY, SPEND, CLICKS, REACH, FREQUENCY, etc.
- `statuses` (array, optional, default [ACTIVE])
- `campaign_ids` (array of uuid, optional)
- `report_start` (ISO 8601, required if granularity=DAY)
- `report_end` (ISO 8601, optional)

**Response:** 201 — `AsyncReportResponse`

### GET /ad_accounts/{ad_account_id}/async_reports/{report_id}
Check async report status and get download URL when complete.

**Response:** 200 — `AsyncReportResponse`

---

## Targeting

### GET /targets/artists
Search for artist targets.

**Query Parameters:**
- `artist_ids` (array of string)
- `q` (string) — Search query (case-insensitive)

**Response:** 200 — `ArtistTargetsResponse`

### GET /targets/genres
Get available genre targets.

### GET /targets/geos
Get available geographic targets. Use this to look up geo IDs for ad set targeting.

**Query Parameters:**
- `country_code` (string, required) — Two-letter ISO country code (e.g., "US", "CA", "GB")
- `q` (string, optional) — Search query for location name or postal code (e.g., "Connecticut", "Hartford", "06103")
- `ids` (array, optional) — List of geo IDs to retrieve
- `limit` (integer, optional) — Max results per page (default: 50, max: 1000)
- `offset` (integer, optional) — Pagination offset

**Response:** 200 — `GeoTargetsResponse`
```json
{
  "geos": [
    {
      "id": "4831725",
      "type": "REGION",
      "name": "Connecticut",
      "parent_geo_name": "United States of America",
      "country_code": "US"
    },
    {
      "id": "533",
      "type": "DMA_REGION",
      "name": "Hartford & New Haven, CT",
      "parent_geo_name": "United States of America",
      "country_code": "US"
    },
    {
      "id": "4845411",
      "type": "CITY",
      "name": "West Hartford",
      "parent_geo_name": "Connecticut",
      "country_code": "US"
    },
    {
      "id": "US:06103",
      "type": "POSTAL_CODE",
      "name": "06103, Capitol Region, Hartford",
      "parent_geo_name": "Connecticut",
      "country_code": "US"
    }
  ],
  "offset": 0,
  "page_size": 20
}
```

**Geo Types:**
- `REGION` — States, provinces, territories
- `DMA_REGION` — Designated Market Areas for media targeting
- `CITY` — Cities and towns
- `POSTAL_CODE` — ZIP codes (format: "US:06103")

**Usage in ad set `geo_targets`:**
```json
{
  "geo_targets": {
    "country_code": "US",
    "region_ids": ["4831725"],           // Connecticut
    "dma_ids": ["533"],                  // Hartford & New Haven DMA
    "city_ids": ["4845411"],             // West Hartford
    "postal_code_ids": ["US:06103"]      // Specific ZIP code
  }
}
```

### GET /targets/interests
Get available interest targets.

### GET /targets/languages
Get available language targets.

### GET /targets/playlists
Search for playlist targets.

---

## Ad Accounts & Businesses

### GET /ad_accounts/{ad_account_id}
Get ad account details.

**Response:** 200 — `AdAccountResponse`

### PATCH /ad_accounts/{ad_account_id}
Update ad account settings.

### POST /businesses
Create a new business.

### GET /businesses
List businesses for current user.

### GET /businesses/{business_id}
Get business by ID.

---

## Estimates

### POST /estimates/audience
Estimate audience size based on targeting parameters.

**Request Body:** `AudienceEstimateRequest` — Same targeting structure as ad set targets.

**Response:** 200 — `AudienceEstimateResponse`

### POST /estimates/bid
Get recommended bid range based on ad set parameters.

**Request Body:** `BidEstimateRequest`

**Response:** 200 — `BidEstimateResponse`

---

## Error Responses

All endpoints return errors in this format:
```json
{
  "error": {
    "message": "Description of the error",
    "code": "ERROR_CODE"
  },
  "path": "/ad_accounts/xxx/campaigns",
  "timestamp": "2025-01-01T00:00:00Z"
}
```

Common HTTP status codes:
- 400 — Bad request (validation error)
- 403 — Forbidden (insufficient permissions)
- 404 — Resource not found
- 500 — Internal server error
