# Spotify Ads API v3 — Endpoint Reference

## Campaigns

### POST /ad_accounts/{ad_account_id}/campaigns
Create a new campaign.

**Path Parameters:**
- `ad_account_id` (uuid, required) — Ad account identifier

**Request Body:** `CreateCampaignRequest`
- `name` (string, 2-200 chars, required)
- `objective` (string, required) — One of: REACH, EVEN_IMPRESSION_DELIVERY, CLICKS, VIDEO_VIEWS, CONVERSIONS, LEAD_GEN, PODCAST_STREAMS, APP_INSTALLS, WEBSITE_VISITS
- `purchase_order` (string, optional)
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
- `asset_format` (string, required) — AUDIO, VIDEO, IMAGE, or CATALOG
- `category` (string, **required**) — Ad category code (e.g. `ADV_1_2`). Fetch valid values from `GET /ad_categories`
- `targets` (object, required) — See Targeting section. **Note:** `geo_targets` is a flat object `{"country_code":"US"}`, NOT an array. `platforms` valid values are `ANDROID`, `DESKTOP`, `IOS`.
- `bid_strategy` (string, required) — Plain string enum: `MAX_BID`, `COST_PER_RESULT`, `AUTOBID`, or `UNSET`. **Not an object.**
- `bid_micro_amount` (int64, required with MAX_BID or COST_PER_RESULT, not required with AUTOBID) — Bid cap in micro-units. With MAX_BID, this is the maximum CPM. Example: $15 bid cap = `15000000`
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

## Drafts (Preferred for New Campaigns)

Draft entities are staging versions of campaigns, ad sets, and ads. Nothing goes live until you publish. The workflow: create drafts → edit → validate → publish.

### POST /ad_accounts/{ad_account_id}/drafts/campaigns
Create a draft campaign.

**Request Body:** `CampaignDraftRequestProperties`
- `name` (string, max 200 chars)
- `purchase_order` (string, max 45 chars, optional)
- `objective` (string, optional) — REACH, EVEN_IMPRESSION_DELIVERY, CLICKS, VIDEO_VIEWS, PODCAST_STREAMS
- `delivery_goal_group` (string, optional) — AWARENESS, CONSIDERATION
- `status` (string, optional)

**Response:** 200 — `CampaignDraft` (includes `id`, `draft_hierarchy_version`)

### GET /ad_accounts/{ad_account_id}/drafts/campaigns
List draft campaigns.

**Query Parameters:**
- `campaign_ids` (array, repeated param) — Filter by campaign IDs
- `channel` (array, repeated param) — Filter by campaign channel
- `statuses` (array, repeated param) — Filter by status
- `sort_field`, `sort_direction`, `limit`, `offset`

**Response:** 200 — `CampaignDraftsResponse` (`campaign_drafts` array)

### GET /ad_accounts/{ad_account_id}/drafts/campaigns/{draft_campaign_id}
Get a draft campaign by ID.

**Response:** 200 — `CampaignDraft`

### PATCH /ad_accounts/{ad_account_id}/drafts/campaigns/{draft_campaign_id}
Update a draft campaign.

**Request Body:** `CampaignDraftRequestProperties` — same fields as create, all optional.

**Response:** 200 — `CampaignDraft`

### POST /ad_accounts/{ad_account_id}/drafts/campaigns/{draft_campaign_id}
Publish or validate a draft campaign hierarchy.

**Request Body:** `PublishCampaignRequest`
- `action` (string, required) — `PUBLISH` or `VALIDATE` (default: VALIDATE)
- `draft_hierarchy_version` (integer, required) — Must match the current version from the draft campaign

**Success Response:** 200 — `PublishCampaignResult`
- `campaign` — Published `CampaignResponse` (present on successful `PUBLISH`; may be absent for successful `VALIDATE`)
- `validation_errors` — `null`

**Validation Failure Response:** 400 — `PublishCampaignResult` with `validation_errors` array:
  - `validation_entity_type` — `CAMPAIGN`, `AD_SET`, or `AD`
  - `validation_entity_id` — UUID of the entity with the error
  - `message` — Human-readable error description

### DELETE /ad_accounts/{ad_account_id}/drafts/campaigns/{draft_campaign_id}
Delete a draft campaign.

**Response:** 204 No Content

### POST /ad_accounts/{ad_account_id}/campaigns/{campaign_id}/drafts
Create a draft from an existing published campaign.

**Response:** 200 — `CampaignDraft`

### POST /ad_accounts/{ad_account_id}/drafts/ad_sets
Create a draft ad set.

**Request Body:** `AdSetDraftCreateRequest`
- `campaign_id` (uuid, **required** — must reference a draft campaign ID)
- `name` (string, max 200 chars)
- `start_time`, `end_time` (ISO 8601 strings)
- `budget` — `{micro_amount, type}` (DAILY or LIFETIME)
- `bid_strategy` (string) — `MAX_BID`, `COST_PER_RESULT`, `AUTOBID`, `UNSET`
- `bid_micro_amount` (int64)
- `asset_format`, `category`, `targets`, `pacing`, `frequency_caps`, `cost_model`, `delivery_goal`, `promotion`, `video_delivery_formats`, `status`

**Response:** 200 — `AdSetDraft` (includes `id`, `draft_hierarchy_version`)

### GET /ad_accounts/{ad_account_id}/drafts/ad_sets
List draft ad sets.

**Query Parameters:** `campaign_ids`, `statuses`, `limit`, `offset`

**Response:** 200 — `AdSetDraftsResponse` (`ad_set_drafts` array)

### GET /ad_accounts/{ad_account_id}/drafts/ad_sets/{draft_ad_set_id}
Get a draft ad set by ID.

### PATCH /ad_accounts/{ad_account_id}/drafts/ad_sets/{draft_ad_set_id}
Update a draft ad set. Same fields as create, all optional.

### DELETE /ad_accounts/{ad_account_id}/drafts/ad_sets/{draft_ad_set_id}
Delete a draft ad set. **Response:** 204

### POST /ad_accounts/{ad_account_id}/ad_sets/{ad_set_id}/drafts
Create a draft from an existing published ad set.

### POST /ad_accounts/{ad_account_id}/drafts/ads
Create a draft ad.

**Request Body:** `AdDraftCreateRequest`
- `ad_set_id` (uuid, **required** — must reference a draft ad set ID)
- `name`, `advertiser_name`, `tagline` (strings)
- `assets` — `{asset_id, logo_asset_id, companion_asset_id, canvas_asset_id}`
- `asset_format`, `call_to_action` (`{key, clickthrough_url, language}`), `third_party_tracking`, `placements`, `weight`, `status`

**Response:** 200 — `AdDraft` (includes `id`, `draft_hierarchy_version`)

### GET /ad_accounts/{ad_account_id}/drafts/ads
List draft ads.

**Query Parameters:** `ad_set_ids`, `statuses`, `limit`, `offset`

**Response:** 200 — `AdDraftsResponse` (`ad_drafts` array)

### GET /ad_accounts/{ad_account_id}/drafts/ads/{draft_ad_id}
Get a draft ad by ID.

### PATCH /ad_accounts/{ad_account_id}/drafts/ads/{draft_ad_id}
Update a draft ad. Same fields as create, all optional.

### DELETE /ad_accounts/{ad_account_id}/drafts/ads/{draft_ad_id}
Delete a draft ad. **Response:** 204

### POST /ad_accounts/{ad_account_id}/ads/{ad_id}/drafts
Create a draft from an existing published ad.

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

### GET /ad_accounts/{ad_account_id}/aggregate_reports/totals
Get deduplicated metrics aggregated across a set of campaigns, ad sets, or ads. Reach and frequency are deduplicated across all specified entities.

**Query Parameters:**
- `entity_type` (string, required) — `CAMPAIGN`, `AD_SET`, or `AD` (AD_ACCOUNT not supported)
- `entity_ids` (array of uuid, required, max 50) — Entity IDs to aggregate across (repeated format)
- `granularity` (string, required) — `LIFETIME` or `DAY` (HOUR not supported)
- `fields` (array, required) — `IMPRESSIONS`, `CLICKS`, `CTR`, `REACH`, `FREQUENCY` (repeated format)
- `report_start` (ISO 8601, required for DAY, optional for LIFETIME)
- `report_end` (ISO 8601, required for DAY, optional for LIFETIME)

**Response:** 200 — `AggregatedTotalsResponse`

### GET /ad_accounts/{ad_account_id}/aggregate_reports
Get aggregated campaign metrics.

**Query Parameters:**
- `entity_type` (string, required) — Entity to report on: `CAMPAIGN`, `AD_SET`, `AD`, or `AD_ACCOUNT`
- `fields` (array, required) — Metrics to include. **Parameter name is `fields`, NOT `report_fields`.** Must use **repeated parameter format** (`fields=IMPRESSIONS&fields=SPEND`), NOT comma-separated.
  Valid common values: `IMPRESSIONS`, `SPEND`, `CLICKS`, `REACH`, `FREQUENCY`, `LISTENERS`, `NEW_LISTENERS`, `STREAMS`, `COMPLETES`, `COMPLETION_RATE`, `STARTS`, `FIRST_QUARTILES`, `MIDPOINTS`, `THIRD_QUARTILES`, `VIDEO_VIEWS`, `CTR`, `OFF_SPOTIFY_IMPRESSIONS`
  Conversion-style values include `PAGE_VIEWS`, `LEADS`, `ADD_TO_CART`, `PURCHASES`, `REVENUE`, `RETURN_ON_AD_SPEND`, `AVERAGE_ORDER_VALUE`, `START_CHECKOUT`, and `SIGN_UPS`. Do not invent singular/plural variants.
  Note: `CPM` from async reports is NOT valid here. Use `COMPLETES` (not `AD_COMPLETES`).
- `granularity` (string) — `HOUR`, `DAY`, or `LIFETIME` (default: `LIFETIME`)
- `report_start` (ISO 8601 datetime, required for DAY/HOUR; do not send with LIFETIME)
- `report_end` (ISO 8601 datetime, required for DAY/HOUR; do not send with LIFETIME)
- `entity_ids` (array of uuid) — Filter to specific entities (repeated format)
- `entity_ids_type` (string) — Type of IDs in entity_ids: `CAMPAIGN`, `AD_SET`, `AD`
- `entity_status_type` (string) — Filter by status
- `include_parent_entity` (boolean) — Include parent entity info for AD_SET/AD
- `continuation_token` (string) — For pagination
- `limit` (integer, 1-50)

**Granularity constraints:**
- `LIFETIME` / `DAY`: date range must be within 90 days
- `LIFETIME`: do not pass `report_start` or `report_end`
- `DAY`: use UTC midnight timestamps for both `report_start` and `report_end`
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

Note: `field_value` is a **float** (e.g., `15234.0`, `0.0`), not a string. Aggregate-report `SPEND` values are already in account currency; do not divide them by 1,000,000.

### GET /ad_accounts/{ad_account_id}/insight_reports
Get audience insight breakdowns.

**Query Parameters:**
- `insight_dimension` (string) — ACT_AND_SET, AGE, AUDIENCE, CITY, COUNTRY, FORMAT, GENDER, GENRE, INTERESTS, METRO, PLACEMENT, PLATFORM, PODCAST_EPISODE_TOPIC, REGION, TONE
- `fields` (array) — **Uses `fields`, NOT `report_fields`.** Repeated parameter format.
  Insight reports do not allow `E_CPCL`, `FREQUENCY`, `OFF_SPOTIFY_IMPRESSIONS`, `PAID_LISTENS_FREQUENCY`, `SKIPS`, `SPEND`, `STARTS`, or `UNMUTES`.
- `entity_ids` (array of uuid, optional) — Insight reports currently support one ID at a time.
- `entity_ids_type` (string, required when `entity_ids` is set) — Use `AD_SET` for insight reports.
- `statuses` (array, optional) — Filter by ad set status.
- `entity_status_type` (string, required when statuses are set) — Use `AD_SET` for insight reports.

Do not send `entity_type`, `report_start`, `report_end`, `granularity`, or `limit` on insight reports. `entity_type=AD_SET` does not substitute for `entity_ids_type=AD_SET`. Do not use dimensions such as `LOCATION`, `GEO`, `DMA`, `STATE`, `ZIP`, `POSTAL_CODE`, `MARKET`, `DEVICE`, `OS`, `ARTIST`, `AGE_RANGE`, or `CITY_NAME`.

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
- `insight_dimension` (string, optional) — Break down by delivery insight: ACT_AND_SET, AGE, AUDIENCE, CITY, COUNTRY, FORMAT, GENDER, GENRE, INTERESTS, METRO, PLACEMENT, PLATFORM, PODCAST_EPISODE_TOPIC, REGION, TONE. Only supported with LIFETIME granularity.

Async report `dimensions` are entity metadata columns only. Do not put geo, demographic, platform, or audience breakdown values such as `CITY`, `COUNTRY`, `REGION`, `GENDER`, `AGE`, or `PLATFORM` in `dimensions`. For async CSV delivery insight breakdowns, set `insight_dimension` with `granularity=LIFETIME`; for direct JSON insight results, use `GET /insight_reports`.

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
Get available genre targets. Returns all genres in one response (no pagination).

**Query Parameters:**
- `ids` (array of string, optional) — Filter by specific genre IDs. Repeated format: `ids=rock&ids=blues`
- `q` (string, optional) — Free-text search (e.g. `q=rock` returns "Indie Rock" and "Rock")

**No other parameters accepted.** This endpoint rejects `limit`, `offset`, and any parameter not listed above with a 400 error.

**Response:** 200 — `GenreTargetsResponse`
```json
{
  "genres": [
    { "id": "rock", "name": "Rock" },
    { "id": "blues", "name": "Blues" }
  ]
}
```

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
Get available interest targets. Returns all interests in one response (no pagination). Interests are organized into categories with optional subtargets.

**Query Parameters:**
- `ids` (array of string, optional) — Filter by specific interest IDs. Repeated format: `ids=<uuid>&ids=<uuid>`
- `q` (string, optional) — Free-text search across both parent interests and subtargets (e.g. `q=gaming` returns "Video Gaming" with its subtargets)

**No other parameters accepted.** This endpoint rejects `limit`, `offset`, and any parameter not listed above with a 400 error.

**Response:** 200 — `InterestTargetsResponse`
```json
{
  "interests": null,
  "interests_with_subtargets": [
    {
      "id": "f08153d9-2dd0-406b-a6b0-f57d6634c221",
      "name": "Books and Literature",
      "subtargets": []
    },
    {
      "id": "55500376-9877-4caf-9bb0-b456f214f8ca",
      "name": "Video Gaming",
      "subtargets": [
        { "id": "040d47eb-7ade-46d9-b15e-3bd9982f8f02", "name": "eSports" },
        { "id": "cdab187f-abb7-4b29-a45f-58b77cbe25d0", "name": "Role-Playing Video Games" }
      ]
    }
  ]
}
```

**Note:** The `interests` key is always null. Actual data is in `interests_with_subtargets`. Both parent IDs and subtarget IDs are valid values for `interest_ids` in ad set targets.

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

### GET /businesses/{business_id}/ad_accounts
List ad accounts under a business for the current user.

**Response:** 200 — `AdAccountsResponse` (array of `AdAccountResponse` with paging)

### POST /businesses/{business_id}/ad_accounts
Create a new ad account under a business.

**Request Body:** `CreateAdAccountRequest`

**Response:** 200 — `AdAccountResponse`

---

## Estimates

**Important:** These are top-level endpoints — they are NOT nested under `/ad_accounts/{ad_account_id}/`. The `ad_account_id` is passed in the request body instead.

### POST /estimates/audience
Estimate audience size, reach, impressions, CPM range, and delivery likelihood based on ad set parameters.

**Request Body:** `AudienceEstimateRequest`

Required fields:
- `ad_account_id` (uuid, required) — The ad account to estimate for
- `start_date` (ISO 8601 datetime, required) — Campaign start date
- `asset_format` (string, required) — AUDIO, VIDEO, IMAGE, or CATALOG
- `objective` (string, required) — REACH, CLICKS, VIDEO_VIEWS, CONVERSIONS, LEAD_GEN, EVEN_IMPRESSION_DELIVERY, PODCAST_STREAMS, APP_INSTALLS, or WEBSITE_VISITS
- `bid_strategy` (string, required) — MAX_BID, COST_PER_RESULT, AUTOBID, or UNSET
- `bid_micro_amount` (int64, required with MAX_BID/COST_PER_RESULT, not required with AUTOBID) — Bid cap in micro-units
- `budget` (object, required) — Requires `micro_amount`, `type` (DAILY or LIFETIME), **and `currency`** (e.g. "USD"). Note: this differs from ad set budget which does not require `currency`.
- `targets` (object, required) — Same Targets structure as ad set creation

Optional fields:
- `end_date` (ISO 8601 datetime) — Campaign end date
- `frequency_caps` (array) — Frequency cap objects
- `category` (string) — Ad category code
- `video_delivery_formats` (object) — For VIDEO format

```json
{
  "ad_account_id": "ce4ff15e-f04d-48b9-9ddf-fb3c85fbd57a",
  "start_date": "2026-01-15T00:00:00Z",
  "end_date": "2026-02-15T23:59:59Z",
  "asset_format": "AUDIO",
  "objective": "REACH",
  "bid_strategy": "MAX_BID",
  "bid_micro_amount": 15000000,
  "budget": {
    "micro_amount": 5000000,
    "type": "DAILY",
    "currency": "USD"
  },
  "frequency_caps": [
    { "frequency_unit": "WEEK", "frequency_period": 1, "max_impressions": 2 }
  ],
  "targets": {
    "age_ranges": [{ "min": 18, "max": 44 }],
    "geo_targets": { "country_code": "US" },
    "platforms": ["ANDROID", "DESKTOP", "IOS"],
    "placements": ["MUSIC"],
    "interest_ids": ["f08153d9-2dd0-406b-a6b0-f57d6634c221"]
  }
}
```

**Response:** 200 — `AudienceEstimateResponse`
```json
{
  "audience_forecast": [
    {
      "forecast_type": "DAILY",
      "estimated_reach_min": 300,
      "estimated_reach_max": 700,
      "estimated_impressions_min": 300,
      "estimated_impressions_max": 700,
      "estimated_frequency_min": 1.0,
      "estimated_frequency_max": 2.3,
      "estimated_cpm_min": 6076000,
      "estimated_cpm_max": 14177000,
      "projected_unique_users": 493,
      "raw_unique_users": 421697
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

`audience_forecast` returns up to 3 entries (DAILY, WEEKLY, MONTHLY) for DAILY budgets, or 1 entry (LIFETIME) for LIFETIME budgets. `raw_unique_users` is the exact count from the past 7 days; `projected_unique_users` is adjusted for frequency caps and budget.

### POST /estimates/bid
Get recommended bid range based on ad set parameters.

**Request Body:** `BidEstimateRequest`

Required fields:
- `asset_format` (string, required) — AUDIO, VIDEO, IMAGE, or CATALOG
- `objective` (string, required) — REACH, CLICKS, VIDEO_VIEWS, CONVERSIONS, LEAD_GEN, EVEN_IMPRESSION_DELIVERY, PODCAST_STREAMS, APP_INSTALLS, or WEBSITE_VISITS
- `bid_strategy` (string, required) — MAX_BID, COST_PER_RESULT, AUTOBID, or UNSET
- `currency` (string, required) — e.g. "USD"
- `targets` (object, required) — Same Targets structure as ad set creation

Optional fields:
- `frequency_caps` (array) — Frequency cap objects
- `category` (string) — Ad category code

```json
{
  "asset_format": "AUDIO",
  "objective": "REACH",
  "bid_strategy": "MAX_BID",
  "currency": "USD",
  "targets": {
    "age_ranges": [{ "min": 18, "max": 44 }],
    "geo_targets": { "country_code": "US" },
    "platforms": ["ANDROID", "DESKTOP", "IOS"],
    "placements": ["MUSIC"]
  }
}
```

**Response:** 200 — `BidEstimateResponse`
```json
{
  "bid_estimate_min": 8014566,
  "bid_estimate_max": 9795581,
  "cost_model": "CPM",
  "currency": "USD"
}
```

Bid amounts are in micro-units. Divide by 1,000,000 for dollar values (e.g. 8014566 = ~$8.01 CPM).

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
