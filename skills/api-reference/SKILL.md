---
name: Spotify Ads API Reference
description: Consult the Spotify Ads API v3 reference for exact endpoints, schemas, fields, enum values, request/response formats, authentication details, or when an operation skill explicitly needs schema clarification. Routine campaign, ad, asset, and reporting operations should use their dedicated skills without also loading this reference.
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
X-Spotify-Ads-Sdk: <sdk-product>/<version>
X-Spotify-Ads-Skill: <skill-name>
```

Use the active platform SDK product and plugin version:
- Codex: read `.codex-plugin/plugin.json`, set `SDK_PRODUCT="codex-plugin"`.
- Claude: read `.claude-plugin/plugin.json`, set `SDK_PRODUCT="claude-code-plugin"`.
- Antigravity: read `plugin.json` (plugin root), set `SDK_PRODUCT="antigravity-cli-plugin"`.

Set `SDK_HEADER="X-Spotify-Ads-Sdk: $SDK_PRODUCT/$PLUGIN_VERSION"` and `SKILL_HEADER="X-Spotify-Ads-Skill: <skill-name>"` (where `<skill-name>` is the directory name of the active skill, e.g. `campaigns`, `dashboard`, `report`). Include `-H "$SDK_HEADER"` and `-H "$SKILL_HEADER"` on all API requests.

To set up authentication, run the configure skill (`/spotify-ads-api:configure` on Claude/Codex, `/configure` on Antigravity), which supports OAuth 2.0 with automatic token refresh, manual OAuth, or direct token input.

## Resource Hierarchy

```
Business
  └── Ad Account
        ├── Campaign
        │     └── Ad Set
        │           └── Ad (references Assets)
        ├── Draft Campaign (staging — not live until published)
        │     └── Draft Ad Set
        │           └── Draft Ad
        ├── Audience
        ├── Asset
        └── Reports
```

Every CRUD operation on campaigns, ad sets, ads, assets, and audiences is scoped under an **ad account ID**.

**Draft workflow (preferred for new campaigns):** Create draft entities → validate the entire hierarchy → publish. See the Drafts endpoint group below.

For draft `VALIDATE` and `PUBLISH`, always fetch the draft campaign immediately before the action and use its current `draft_hierarchy_version`. `PUBLISH` creates live entities and always requires explicit user confirmation, even when automatic execution is enabled.

## Key Conventions

- **Budgets use micro-amounts**: Multiply dollar values by 1,000,000. A $50 budget = `50000000` micro-amount.
- **Timestamps**: ISO 8601 in UTC (e.g., `2025-09-23T04:56:07Z`).
- **IDs**: UUID format (e.g., `ce4ff15e-f04d-48b9-9ddf-fb3c85fbd57a`).
- **Pagination**: All list endpoints support `limit` (1-50, default 50) and `offset` (default 0).
- **Sorting**: Most list endpoints support `sort_direction` (ASC/DESC) and entity-specific sort fields.
- **Updates use PATCH**: Partial updates with minimum 1 property required.
- **No DELETE on live campaigns/ad sets/ads**: Use status changes (ARCHIVED, PAUSED) instead. Draft entities _can_ be deleted.

## Public Endpoint Groups

### Campaigns
- `POST /ad_accounts/{id}/campaigns` — Create campaign (required: name, objective)
- `GET /ad_accounts/{id}/campaigns` — List campaigns (filterable by status, name, IDs)
- `GET /ad_accounts/{id}/campaigns/{campaign_id}` — Get campaign by ID
- `PATCH /ad_accounts/{id}/campaigns/{campaign_id}` — Update campaign (name, status)

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

### Drafts (Preferred for New Campaigns)

Draft entities are staging versions that are not live until explicitly published. The full lifecycle:
create drafts → edit → validate → publish.

**Campaign drafts:**
- `POST /ad_accounts/{id}/drafts/campaigns` — Create draft campaign
- `GET /ad_accounts/{id}/drafts/campaigns` — List draft campaigns
- `GET /ad_accounts/{id}/drafts/campaigns/{draft_id}` — Get draft campaign
- `PATCH /ad_accounts/{id}/drafts/campaigns/{draft_id}` — Update draft campaign
- `POST /ad_accounts/{id}/drafts/campaigns/{draft_id}` — Publish or validate (body: `{"action": "PUBLISH"|"VALIDATE", "draft_hierarchy_version": N}`)
- `DELETE /ad_accounts/{id}/drafts/campaigns/{draft_id}` — Delete draft campaign

**Ad set drafts:**
- `POST /ad_accounts/{id}/drafts/ad_sets` — Create draft ad set (requires `campaign_id` referencing a draft campaign)
- `GET /ad_accounts/{id}/drafts/ad_sets` — List draft ad sets
- `GET /ad_accounts/{id}/drafts/ad_sets/{draft_id}` — Get draft ad set
- `PATCH /ad_accounts/{id}/drafts/ad_sets/{draft_id}` — Update draft ad set
- `DELETE /ad_accounts/{id}/drafts/ad_sets/{draft_id}` — Delete draft ad set

**Ad drafts:**
- `POST /ad_accounts/{id}/drafts/ads` — Create draft ad (requires `ad_set_id` referencing a draft ad set)
- `GET /ad_accounts/{id}/drafts/ads` — List draft ads
- `GET /ad_accounts/{id}/drafts/ads/{draft_id}` — Get draft ad
- `PATCH /ad_accounts/{id}/drafts/ads/{draft_id}` — Update draft ad
- `DELETE /ad_accounts/{id}/drafts/ads/{draft_id}` — Delete draft ad

**Create draft from published entity:**
- `POST /ad_accounts/{id}/campaigns/{campaign_id}/drafts` — Draft from live campaign
- `POST /ad_accounts/{id}/ad_sets/{ad_set_id}/drafts` — Draft from live ad set
- `POST /ad_accounts/{id}/ads/{ad_id}/drafts` — Draft from live ad

### Other Public Endpoints
- `GET/PATCH /ad_accounts/{id}` — Get/update ad account
- `POST/GET /businesses` — Create/list businesses
- `GET /businesses/{id}` — Get business by ID
- `GET /targets/artists` — Search artist targets
- `GET /ad_categories` — List ad categories
- `POST /estimates/audience` — Estimate audience size for targeting parameters (recommended before creating ad sets to validate reach)
- `POST /estimates/bid` — Get bid recommendations
- `POST /ad_accounts/{id}/reserved_prices` — Get pricing for reserved ad products (fCPM)

## Making API Calls

Read the user's plugin settings from the active platform settings file created by the configure skill:
- Codex: prefer `.codex/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.agents/spotify-ads-api.local.md`.
- Claude: prefer `.claude/spotify-ads-api.local.md`, then fall back to `.codex/spotify-ads-api.local.md`, then `.agents/spotify-ads-api.local.md`.
- Antigravity: prefer `.agents/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.codex/spotify-ads-api.local.md`.

Use the settings file to get:
- `access_token` — Bearer token for authentication
- `ad_account_id` — Default ad account ID
- `auto_execute` — Whether to execute API calls automatically or present them first (default: false)

If the settings file does not exist, instruct the user to run the configure skill first (`/spotify-ads-api:configure` on Claude/Codex, `/configure` on Antigravity).

Construct curl commands using the appropriate base URL. Example:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X GET \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
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
