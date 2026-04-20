---
name: Spotify Ads API Reference
description: This skill should be used when the user asks to "call the Spotify Ads API", "create a Spotify ad campaign", "manage Spotify ads", "pull Spotify ad reports", "set up ad sets or ads", "upload ad assets", "target audiences on Spotify", "check campaign status", "get ad account info", "look up API schema or fields", "check what targeting options exist", or asks about Spotify advertising endpoints, request/response formats, enum values, or authentication.
---

# Spotify Ads API v3 Reference

## Overview

The Spotify Ads API v3 enables programmatic management of advertising campaigns on Spotify. It follows a strict resource hierarchy and uses OAuth 2.0 bearer token authentication.

## Base URL

`https://api-partner.spotify.com/ads/v3`

## Authentication

All requests require a Bearer token and the SDK tracking header:

```
Authorization: Bearer <access_token>
X-Spotify-Ads-Sdk: claude-code-plugin/<version>
```

The `<version>` is the `version` field from `.claude-plugin/plugin.json`. Set `SDK_HEADER="X-Spotify-Ads-Sdk: claude-code-plugin/$PLUGIN_VERSION"` and include `-H "$SDK_HEADER"` on all API requests.

To set up authentication, run `/spotify-ads-api:configure` which supports OAuth 2.0 with automatic token refresh, manual OAuth, or direct token input.

## Resource Hierarchy

```
Business
  └── Ad Account
        ├── Campaign
        │     └── Ad Set
        │           └── Ad (references Assets)
        ├── Audience
        ├── Asset
        └── Reports
```

Every CRUD operation on campaigns, ad sets, ads, assets, and audiences is scoped under an **ad account ID**.

## Key Conventions

- **Budgets use micro-amounts**: Multiply dollar values by 1,000,000. A $50 budget = `50000000` micro-amount.
- **Timestamps**: ISO 8601 in UTC (e.g., `2025-09-23T04:56:07Z`).
- **IDs**: UUID format (e.g., `ce4ff15e-f04d-48b9-9ddf-fb3c85fbd57a`).
- **Pagination**: All list endpoints support `limit` (1-50, default 50) and `offset` (default 0).
- **Sorting**: Most list endpoints support `sort_direction` (ASC/DESC) and entity-specific sort fields.
- **Updates use PATCH**: Partial updates with minimum 1 property required.
- **No DELETE on campaigns/ad sets/ads**: Use status changes (ARCHIVED, PAUSED) instead.

## Public Endpoint Groups

### Campaigns
- `POST /ad_accounts/{id}/campaigns` — Create campaign (required: name, objective)
- `GET /ad_accounts/{id}/campaigns` — List campaigns (filterable by status, name, IDs)
- `GET /ad_accounts/{id}/campaigns/{campaign_id}` — Get campaign by ID
- `PATCH /ad_accounts/{id}/campaigns/{campaign_id}` — Update campaign (name, status, restricted_ad_category)

### Ad Sets
- `POST /ad_accounts/{id}/ad_sets` — Create ad set (required: name, start_time, budget, asset_format, targets, bid_strategy)
- `GET /ad_accounts/{id}/ad_sets/{ad_set_id}` — Get ad set by ID
- `PATCH /ad_accounts/{id}/ad_sets/{ad_set_id}` — Update ad set

### Ads
- `POST /ad_accounts/{id}/ads` — Create ad (required: name, assets; also needs tagline, advertiser_name, ad_set_id, call_to_action)
- `GET /ad_accounts/{id}/ads` — List ads (filterable by ad_set_ids, campaign_ids, statuses)
- `GET /ad_accounts/{id}/ads/{ad_id}` — Get ad by ID
- `PATCH /ad_accounts/{id}/ads/{ad_id}` — Update ad

### Assets
- `POST /ad_accounts/{id}/assets` — Create asset (image, audio, or video)
- `GET /ad_accounts/{id}/assets` — List assets
- `GET /ad_accounts/{id}/assets/{asset_id}` — Get asset by ID
- `PATCH /ad_accounts/{id}/assets/{asset_id}` — Update asset
- `PATCH /ad_accounts/{id}/assets` — Bulk archive/unarchive

### Audiences
- `POST /ad_accounts/{id}/audiences` — Create audience (CUSTOM or LOOKALIKE)
- `GET /ad_accounts/{id}/audiences` — List audiences
- `DELETE /ad_accounts/{id}/audiences/{audience_id}` — Delete audience

### Reports
- `GET /ad_accounts/{id}/aggregate_reports` — Aggregated metrics by entity
- `GET /ad_accounts/{id}/insight_reports` — Audience insight breakdowns
- `POST /ad_accounts/{id}/async_reports` — Create async CSV report
- `GET /ad_accounts/{id}/async_reports/{report_id}` — Check async report status

### Other Public Endpoints
- `GET/PATCH /ad_accounts/{id}` — Get/update ad account
- `POST/GET /businesses` — Create/list businesses
- `GET /businesses/{id}` — Get business by ID
- `GET /targets/artists` — Search artist targets
- `GET /ad_categories` — List ad categories
- `POST /estimates/audience` — Estimate audience size for targeting parameters (recommended before creating ad sets to validate reach)
- `POST /estimates/bid` — Get bid recommendations

## Making API Calls

Read the user's plugin settings from `.claude/spotify-ads-api.local.md` (created by the `/spotify-ads-api:configure` command) to get:
- `access_token` — Bearer token for authentication
- `ad_account_id` — Default ad account ID
- `auto_execute` — Whether to execute API calls automatically or present them first (default: false)

If the settings file does not exist, instruct the user to run `/spotify-ads-api:configure` first.

Construct curl commands using the appropriate base URL. Example:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X GET \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "$SDK_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/$AD_ACCOUNT_ID/campaigns?limit=50"
```

For error response format and common HTTP status codes, see `references/endpoints.md` (Error Responses section).

## Additional Resources

### Reference Files

For detailed request/response schemas and field definitions, consult:
- **`references/endpoints.md`** — Complete endpoint details with all parameters and response schemas
- **`references/schemas.md`** — Request/response body schemas with field types, constraints, and required fields
- **`references/enums.md`** — All enum values for status fields, asset formats, targeting options, report dimensions/metrics

### Example Files

Working examples with complete curl commands and expected responses:
- **`examples/full-campaign-flow.md`** — End-to-end: create campaign, ad set, and ad with targeting
- **`examples/aggregate-report.md`** — Pull aggregate metrics and create async CSV reports
