# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

A Claude Code plugin for the Spotify Ads API v3. All source files are markdown — there is no compiled code, no package manager, no build step, no tests. The plugin translates natural language into REST API calls for managing campaigns, ad sets, ads, assets, audiences, and reporting.

Install with: `claude --plugin-dir /path/to/sp-ads-api-plugin`

## Architecture

The plugin follows the Claude Code plugin structure with four component types:

- **Skills** (`skills/`) — User-invokable slash commands and reference documentation, each in its own directory with a `SKILL.md` file:
  - `skills/configure/` — OAuth 2.0 setup with automated and manual flows, plus helper scripts in `scripts/`
  - `skills/campaigns/` — Campaign CRUD operations
  - `skills/ads/` — Ad set and ad management
  - `skills/build-campaign/` — Full campaign builder from natural language descriptions
  - `skills/report/` — Aggregate, insight, and async CSV reporting
  - `skills/assets/` — Upload, list, and manage creative assets (audio, video, images)
  - `skills/dashboard/` — Quick performance overview with pacing for active campaigns
  - `skills/api-reference/` — Comprehensive API v3 reference documentation with `references/` (endpoints, schemas, enums) and `examples/` (full flows). Activates automatically when the Spotify Ads API is mentioned.
- **Agent** (`agents/spotify-ads-request-builder.md`) — A natural language agent that triggers automatically when users describe advertising tasks conversationally. Handles multi-step operations (campaign -> ad set -> ad) by chaining API calls and passing IDs between steps.
- **Hooks** (`hooks/hooks.json`) — A `PreToolUse` hook that automatically refreshes expired OAuth tokens before Spotify API calls.
- **Settings** (`.claude/spotify-ads-api.local.md`) — Per-user local config with YAML frontmatter storing OAuth credentials (access_token, refresh_token, client_id, token_expires_at), ad_account_id, and auto_execute. The client_secret is stored in the macOS Keychain (service: `spotify-ads-api-client-secret`, account: `spotify-ads-api`), not in this file. Template lives in `templates/settings-template.md`. This file is gitignored.

## API Conventions to Know

These non-obvious API quirks were discovered through real testing and are critical when modifying any command or agent:

- **Micro-amounts**: Budget and bid values in entity payloads (`budget.micro_amount`, `bid_micro_amount`) are in micro-units ($1 = 1,000,000). However, SPEND values returned by `aggregate_reports` are already in dollars — do NOT divide those by 1,000,000.
- **`bid_strategy`** is a plain string enum (`MAX_BID`, `COST_PER_RESULT`, `UNSET`), not an object. Default to `MAX_BID` with a required `bid_micro_amount`.
- **`geo_targets`** is a flat object (not an array) with a required `country_code` and optional refinement arrays (`region_ids`, `dma_ids`, `city_ids`, `postal_code_ids`). Use `GET /targets/geos?country_code=<code>&q=<query>` to look up geo IDs. Geo types: `REGION` (states/provinces), `DMA_REGION` (media markets), `CITY`, `POSTAL_CODE`. Example: `{"country_code": "US", "region_ids": ["4831725"]}` targets Connecticut. NEVER fall back to country-only without looking up the user's requested location first.
- **`platforms`** valid values are `ANDROID`, `DESKTOP`, `IOS` — not "MOBILE" or "CONNECTED_DEVICE".
- **`category`** is required on ad sets — must be a valid `ADV_X_Y` code from `GET /ad_categories`.
- **`call_to_action`** uses field `key` (not `type`) and `clickthrough_url` (not `url`).
- **`companion_asset_id`** is required for AUDIO format ads.
- **Array query params** use repeated parameter names (`&fields=X&fields=Y`), not comma-separated.
- **Report field name** is `fields`, not `report_fields`.
- **No DELETE** on campaigns/ad sets/ads — use status changes (ARCHIVED, PAUSED).
- **Base URL**: `https://api-partner.spotify.com/ads/v3`.
- **Tracking header**: Every API request must include `-H "X-Spotify-Ads-Sdk: claude-code-plugin/$PLUGIN_VERSION"` alongside the Authorization header, where `$PLUGIN_VERSION` is the `version` field from `.claude-plugin/plugin.json`.
- **`entity_status_type` must match `entity_type`** in `aggregate_reports` queries. For example, use `entity_status_type=AD_SET` when `entity_type=AD_SET` — using `entity_status_type=CAMPAIGN` with `entity_type=AD_SET` causes a filter validation error.
- **Audience estimates**: The build-campaign and ads skills run `POST /estimates/audience` before creating ad sets to validate targeting. This catches "min audience threshold" errors before they happen.

## OpenAPI Spec

- `skills/api-reference/references/external-v3.yaml` — Public OpenAPI v3 spec (~8.6K lines), committed to repo.

## Execution Pattern

All skills follow the same pattern: read settings file -> construct curl command with base URL `https://api-partner.spotify.com/ads/v3` -> if `auto_execute` is false, show curl and confirm before executing -> format and display response. This pattern is duplicated across skills rather than abstracted, so changes to the execution flow must be applied to each skill individually.

**Curl status code capture**: All API curl commands (except file uploads) must use `-w "\nHTTP_STATUS:%{http_code}"` to append the HTTP status code to the response. This makes success/failure unambiguous:

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "X-Spotify-Ads-Sdk: claude-code-plugin/$PLUGIN_VERSION" \
  "$BASE_URL/..."
```

After execution, check the `HTTP_STATUS:` line first:
- **2xx**: Request succeeded — parse and display the response body.
- **4xx/5xx**: Request failed — display the error from the response body. **Never retry a POST or PATCH that returned a non-timeout 4xx** — the request was received and rejected, not lost.
- **Retry safety**: Only retry on network errors or 5xx responses, and only for idempotent methods (GET). Never automatically retry POST or PATCH — these are non-idempotent and may have already been applied server-side (e.g., a 500 after the entity was created). On POST/PATCH failure, check for the created/modified resource first before suggesting a retry.

## Ad Account Discovery

There is no `GET /ad_accounts` list endpoint. To discover a user's ad accounts during onboarding:
1. `GET /businesses` — lists businesses the authenticated user belongs to
2. `GET /businesses/{business_id}/ad_accounts` — lists ad accounts under a specific business

This two-step flow is used by the configure skill during setup.
