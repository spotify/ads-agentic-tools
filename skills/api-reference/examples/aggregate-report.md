# Example: Pulling an Aggregate Report

This example shows how to pull aggregated campaign performance metrics.

## Get Daily Campaign Metrics

```bash
curl -s -X GET \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://api-partner.spotify.com/ads-sandbox/v3/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=CAMPAIGN&\
report_fields=IMPRESSIONS,SPEND,CLICKS,REACH,CTR,CPM&\
report_start=2025-01-01T00:00:00Z&\
report_end=2025-01-31T23:59:59Z&\
granularity=DAY&\
limit=50"
```

**Expected Response (200):**
```json
{
  "continuation_token": null,
  "report_start": "2025-01-01T00:00:00Z",
  "report_end": "2025-01-31T23:59:59Z",
  "granularity": "DAY",
  "rows": [
    {
      "entity_type": "CAMPAIGN",
      "entity_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
      "entity_name": "Summer Sale 2025",
      "entity_status": "ACTIVE",
      "start_time": "2025-01-01T00:00:00Z",
      "end_time": "2025-01-02T00:00:00Z",
      "stats": [
        { "field_type": "IMPRESSIONS", "field_value": "15234" },
        { "field_type": "SPEND", "field_value": "4500000" },
        { "field_type": "CLICKS", "field_value": "312" },
        { "field_type": "REACH", "field_value": "12100" },
        { "field_type": "CTR", "field_value": "0.0205" },
        { "field_type": "CPM", "field_value": "295400" }
      ]
    }
  ],
  "warnings": []
}
```

Note: `SPEND` and `CPM` values are in micro-amounts. Divide by 1,000,000 to get dollar values.
- SPEND 4500000 = $4.50
- CPM 295400 = $0.2954

## Paginating Large Reports

If `continuation_token` is non-null, there are more results. Pass it as a query parameter:

```bash
curl -s -X GET \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://api-partner.spotify.com/ads-sandbox/v3/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=CAMPAIGN&\
report_fields=IMPRESSIONS,SPEND&\
report_start=2025-01-01T00:00:00Z&\
report_end=2025-01-31T23:59:59Z&\
granularity=DAY&\
continuation_token=eyJsYXN0..."
```

## Creating an Async CSV Report

For large datasets, use async reports:

```bash
curl -s -X POST \
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
  "https://api-partner.spotify.com/ads-sandbox/v3/ad_accounts/$AD_ACCOUNT_ID/async_reports"
```

Then check status with the returned report ID:

```bash
curl -s -X GET \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "https://api-partner.spotify.com/ads-sandbox/v3/ad_accounts/$AD_ACCOUNT_ID/async_reports/$REPORT_ID"
```
