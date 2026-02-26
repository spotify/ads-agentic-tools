# Spotify Ads API v3 — Enum Values

## Campaign Enums

### CampaignStatus
- `UNSET`
- `ACTIVE`
- `PAUSED`
- `ARCHIVED`
- `AGENT_CONTROLLED`
- `ACTIVE_RESTRICTED`
- `PENDING_ADVERTISER_REVIEW`
- `UNRECOGNIZED`

### CampaignDerivedStatus
- `ACTIVE`
- `REJECTED`
- `READY`
- `COMPLETED`
- `PENDING_APPROVAL`
- `PENDING_ADVERTISER_APPROVAL`
- `STOPPED`
- `UNKNOWN`

### OptimizationPrefs (Campaign Objective)
- `REACH`
- `EVEN_IMPRESSION_DELIVERY`
- `CLICKS`
- `VIDEO_VIEWS`
- `CONVERSIONS`
- `LEAD_GEN`

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

### TimeDimensionType (Granularity)
- `HOUR`
- `DAY`
- `LIFETIME`

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
- `IMPRESSIONS_ON_SPOTIFY`
- `IMPRESSIONS_OFF_SPOTIFY`
- `SPEND`
- `CLICKS`
- `REACH`
- `FREQUENCY`
- `LISTENERS`
- `NEW_LISTENERS`
- `STREAMS`
- `AD_COMPLETES`
- `CTR`
- `CPM`
- `COMPLETION_RATE`

### AsyncReportEntityStatus
- `ACTIVE`
- `COMPLETED`
- `PENDING_APPROVAL`

### InsightDimensionType
- `GENDER`
- `PLATFORM`
- `LOCATION`
- `ARTIST`
- `GENRE`

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
- `DESKTOP`
- `MOBILE`
- `CONNECTED_DEVICE`

### Gender
- `MALE`
- `FEMALE`
- `NON_BINARY`
