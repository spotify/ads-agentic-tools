# Spotify Ads API v3 — Enum Values

## Campaign Enums

### CampaignStatus
- `UNSET`
- `ACTIVE`
- `PAUSED`
- `ARCHIVED`
- `UNRECOGNIZED`

### CampaignDerivedStatus
- `ACTIVE`
- `REJECTED`
- `READY`
- `COMPLETED`
- `PENDING_APPROVAL`
- `STOPPED`
- `UNKNOWN`

### OptimizationPrefs (Campaign Objective)
- `REACH` — Maximize unique listeners who hear or see the ad. AUDIO and VIDEO formats. MAX_BID only.
- `EVEN_IMPRESSION_DELIVERY` — Default. Distributes impressions evenly across the flight. All asset formats. MAX_BID only.
- `CLICKS` — Drive users to a landing page. AUDIO and VIDEO. MAX_BID or COST_PER_RESULT.
- `VIDEO_VIEWS` — Completed video views. VIDEO only, no DESKTOP. MUSIC placement only. MAX_BID only.
- `CONVERSIONS` — Conversion-optimized traffic.
- `LEAD_GEN` — Lead generation. AUDIO format. MAX_BID only.
- `PODCAST_STREAMS` — Podcast streams. AUDIO format. MAX_BID only.
- `APP_INSTALLS` — Mobile app installs. IOS or ANDROID only (not both, no DESKTOP). Requires mobile_app_id. MAX_BID only.
- `WEBSITE_VISITS` — Website visits. AUDIO and VIDEO formats. MAX_BID only.

---

## Ad Set Enums

### AdSetStatus
- `ACTIVE`
- `PENDING`
- `REJECTED`
- `ARCHIVED`
- `PAUSED`
- `COMPLETED`
- `READY`

### AssetFormat
- `AUDIO`
- `VIDEO`
- `IMAGE`
- `AUDIO_PODCAST`
- `AUDIO_PROGRAMMATIC`
- `SURVEY`
- `URI`
- `MULTI`
- `CATALOG`
- `TEXT`

### BidStrategy
**Important:** This is a plain **string enum**, NOT an object. Use as `"bid_strategy": "MAX_BID"`.
- `MAX_BID` — The `bid_micro_amount` acts as a bid cap (maximum CPM). **This is the typical default.** Always set `bid_micro_amount` when using MAX_BID.
- `COST_PER_RESULT` — Only compatible with the CLICKS campaign objective. The `bid_micro_amount` acts as a target Cost Per Click.
- `AUTOBID` — Bids are automatically set to optimize delivery. `bid_micro_amount` is not required.
- `UNSET` — Pre-auction ad sets will not have a bid strategy set.

### BudgetType
- `DAILY`
- `LIFETIME`

### CostModel
- `CPM`
- `CPC`
- `CPA`
- `CPL`

### Delivery
- `ON`
- `OFF`

### Pacing
- `PACING_EVEN`
- `PACING_ACCELERATED`

---

## Ad Enums

### AdStatus
- `APPROVED`
- `ARCHIVED`
- `PENDING`
- `PENDING_APPROVAL`
- `REJECTED`

### Placement
- `MUSIC`
- `PODCAST`
- `VIDEO`

---

## Asset Enums

### AssetType
- `IMAGE`
- `AUDIO`
- `VIDEO`

### AssetStatus
- `READY`
- `PROCESSING`
- `REJECTED`

### AssetSubtype (for audio assets)
- `ADSTUDIO_SUPPLIED_AUDIO`
- `BACKGROUND_MUSIC`
- `USER_UPLOADED_AUDIO`

### MediaFileType
- `JPEG`
- `PNG`
- `MP4`
- `QUICKTIME`
- `MP3`
- `OGG`
- `WAV`

---

## Audience Enums

### AudienceType
- `CUSTOM`
- `LOOKALIKE`

### AudienceStatus
- `ACTIVE`
- `INACTIVE`
- `EXPIRED`

---

## Report Enums

### ReportFieldType (Aggregate & Insight Reports)
Used with the `fields` query parameter on aggregate and insight report endpoints.
**Important:** These are different from AsyncReportMetric values. Do NOT use async metric names (like `AD_COMPLETES`, `CPM`) in aggregate reports.

- `IMPRESSIONS`
- `SPEND` — aggregate report values are already in account currency; do not divide by 1,000,000
- `CLICKS`
- `REACH`
- `FREQUENCY`
- `LISTENERS`
- `NEW_LISTENERS`
- `STREAMS`
- `COMPLETES` — (NOT `AD_COMPLETES`)
- `COMPLETION_RATE`
- `STARTS`
- `FIRST_QUARTILES`
- `MIDPOINTS`
- `THIRD_QUARTILES`
- `VIDEO_VIEWS`
- `CTR`
- `OFF_SPOTIFY_IMPRESSIONS`

### ReportEntityType
- `CAMPAIGN`
- `AD_SET`
- `AD`
- `AD_ACCOUNT`

### TimeDimensionType (Granularity)
- `HOUR` — date range must be within the last 2 weeks
- `DAY` — date range must be within 90 days
- `LIFETIME` — date range must be within 90 days

### AsyncReportGranularity
- `DAY`
- `LIFETIME`

### AsyncReportDimension
- `AD_ACCOUNT_NAME`
- `AD_ACCOUNT_CURRENCY`
- `CAMPAIGN_NAME`
- `CAMPAIGN_STATUS`
- `CAMPAIGN_OBJECTIVE`
- `AD_SET_NAME`
- `AD_SET_STATUS`
- `AD_SET_BUDGET`
- `AD_SET_COST_MODEL`
- `AD_NAME`

### AsyncReportMetric
**Important:** These are for async CSV reports only. For aggregate reports, use `ReportFieldType` values instead.

- `IMPRESSIONS_ON_SPOTIFY`
- `IMPRESSIONS_OFF_SPOTIFY`
- `SPEND`
- `CLICKS`
- `REACH`
- `FREQUENCY`
- `LISTENERS`
- `NEW_LISTENERS`
- `STREAMS`
- `AD_COMPLETES` — (in aggregate reports, use `COMPLETES` instead)
- `CTR`
- `CPM`
- `COMPLETION_RATE`

### AsyncReportEntityStatus
- `ACTIVE`
- `PAUSED`
- `COMPLETED`
- `PENDING_APPROVAL`
- `REJECTED`
- `ARCHIVED`

### InsightDimensionType
- `ACT_AND_SET`
- `AGE`
- `AUDIENCE`
- `CITY`
- `COUNTRY`
- `FORMAT`
- `GENDER`
- `GENRE`
- `INTERESTS`
- `METRO`
- `PLACEMENT`
- `PLATFORM`
- `PODCAST_EPISODE_TOPIC`
- `REGION`
- `TONE`

---

## Sorting Enums

### SortDirection
- `ASC`
- `DESC`

### CampaignSortField
- `CREATED_AT`
- `UPDATED_AT`
- `NAME`

### AdSetSortField
- `CREATED_AT`
- `UPDATED_AT`
- `NAME`

### AdSortField
- `CREATED_AT`
- `UPDATED_AT`

### AudienceSortField
- `CREATED_AT`
- `UPDATED_AT`
- `NAME`

---

## Targeting Enums

### Platform
- `ANDROID`
- `DESKTOP`
- `IOS`

**Important:** Do NOT use `MOBILE` or `CONNECTED_DEVICE` — those are not valid API values.

### AdCallToActionKey
- `APPLY_NOW`
- `BOOK_NOW`
- `BUY_NOW`
- `BUY_TICKETS`
- `CLICK_NOW`
- `DOWNLOAD`
- `FIND_STORES`
- `GET_COUPON`
- `GET_INFO`
- `LEARN_MORE`
- `LISTEN_NOW`
- `MORE_INFO`
- `ORDER_NOW`
- `PRE_SAVE`
- `SAVE_NOW`
- `SHARE`
- `SHOP_NOW`
- `SIGN_UP`
- `VISIT_PROFILE`
- `VISIT_SITE`
- `WATCH_NOW`

**Important:** The field name in requests is `key`, NOT `type` or `text`.

### Gender
- `MALE`
- `FEMALE`
- `NON_BINARY`
