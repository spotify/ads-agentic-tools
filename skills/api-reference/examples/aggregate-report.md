# Example: Pulling an Aggregate Report

This example shows how to pull aggregated campaign performance metrics.

## Get Lifetime Ad Set Metrics

**Important:** The `fields` parameter must use **repeated parameter names** (`fields=X&fields=Y`), NOT comma-separated values. The parameter is called `fields`, NOT `report_fields`.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}"-X GET \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=AD_SET&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&fields=FREQUENCY&fields=COMPLETES&\
granularity=LIFETIME&\
limit=50"
```

**Expected Response (200):**
```json
{
  "continuation_token": null,
  "report_start": "2025-01-01T00:00:00Z",
  "report_end": "2025-03-31T23:59:59Z",
  "granularity": "LIFETIME",
  "rows": [
    {
      "entity_type": "AD_SET",
      "entity_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "entity_name": "Summer Sale - Audio US 18-34",
      "entity_status": "ACTIVE",
      "start_time": "2025-01-01T00:00:00Z",
      "end_time": "2025-03-31T23:59:59Z",
      "stats": [
        { "field_type": "IMPRESSIONS", "field_value": 15234.0 },
        { "field_type": "SPEND", "field_value": 4500000.0 },
        { "field_type": "CLICKS", "field_value": 312.0 },
        { "field_type": "REACH", "field_value": 12100.0 },
        { "field_type": "FREQUENCY", "field_value": 1.26 },
        { "field_type": "COMPLETES", "field_value": 8450.0 }
      ]
    }
  ],
  "warnings": []
}
```

**Key notes on field values:**
- `field_value` is a **float** (e.g., `15234.0`, `0.0`), NOT a string.
- `SPEND` is in micro-amounts. Divide by 1,000,000 for dollar values (4500000.0 = $4.50).
- Rows with zero impressions are common — filter them out for cleaner output.

## Get Daily Campaign Metrics with Date Range

When using `DAY` or `LIFETIME` granularity, the date range must be within 90 days.
When using `HOUR` granularity, the date range must be within the last 2 weeks.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}"-X GET \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=CAMPAIGN&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&\
report_start=2025-01-01T00:00:00Z&\
report_end=2025-01-31T23:59:59Z&\
granularity=DAY&\
limit=50"
```

## Paginating Large Reports

If `continuation_token` is non-null, there are more results. Pass it as a query parameter:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}"-X GET \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=CAMPAIGN&\
fields=IMPRESSIONS&fields=SPEND&\
granularity=LIFETIME&\
continuation_token=eyJsYXN0...&\
limit=50"
```

## Valid Fields for Aggregate Reports

These are the valid values for the `fields` parameter on aggregate/insight report endpoints:

`IMPRESSIONS`, `SPEND`, `CLICKS`, `REACH`, `FREQUENCY`, `LISTENERS`, `NEW_LISTENERS`,
`STREAMS`, `COMPLETES`, `COMPLETION_RATE`, `STARTS`, `FIRST_QUARTILES`, `MIDPOINTS`,
`THIRD_QUARTILES`, `VIDEO_VIEWS`, `CTR`, `OFF_SPOTIFY_IMPRESSIONS`

**Do NOT use async report metric names** like `AD_COMPLETES`, `CPM`, `IMPRESSIONS_ON_SPOTIFY` — those are only for the async CSV report endpoint.

## Creating an Async CSV Report

For large datasets, use async reports. Note: async reports use **different metric names** than aggregate reports.

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}"-X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "january_2025_report",
    "granularity": "DAY",
    "dimensions": ["CAMPAIGN_NAME", "AD_SET_NAME", "AD_NAME"],
    "metrics": ["IMPRESSIONS_ON_SPOTIFY", "SPEND", "CLICKS", "REACH", "FREQUENCY"],
    "report_start": "2025-01-01T00:00:00Z",
    "report_end": "2025-01-31T23:59:59Z",
    "statuses": ["ACTIVE", "COMPLETED"]
  }' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/async_reports"
```

Then check status with the returned report ID:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}"-X GET \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/async_reports/$REPORT_ID"
```
