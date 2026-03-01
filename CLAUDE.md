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
  - `skills/api-reference/` — Comprehensive API v3 reference documentation with `references/` (endpoints, schemas, enums) and `examples/` (full flows). Activates automatically when the Spotify Ads API is mentioned.
- **Agent** (`agents/spotify-ads-request-builder.md`) — A natural language agent that triggers automatically when users describe advertising tasks conversationally. Handles multi-step operations (campaign -> ad set -> ad) by chaining API calls and passing IDs between steps.
- **Hooks** (`hooks/hooks.json`) — A `PreToolUse` hook that automatically refreshes expired OAuth tokens before Spotify API calls.
- **Settings** (`.claude/spotify-ads-api.local.md`) — Per-user local config with YAML frontmatter storing OAuth credentials (access_token, refresh_token, client_id, client_secret, token_expires_at), ad_account_id, environment, and auto_execute. Template lives in `templates/settings-template.md`. This file is gitignored.

## API Conventions to Know

These non-obvious API quirks were discovered through real testing and are critical when modifying any command or agent:

- **Micro-amounts**: All budget and bid values are in micro-units ($1 = 1,000,000). Both `budget.micro_amount` and `bid_micro_amount` use this.
- **`bid_strategy`** is a plain string enum (`MAX_BID`, `COST_PER_RESULT`, `UNSET`), not an object. Default to `MAX_BID` with a required `bid_micro_amount`.
- **`geo_targets`** is a flat object `{"country_code": "US"}`, not an array.
- **`platforms`** valid values are `ANDROID`, `DESKTOP`, `IOS` — not "MOBILE" or "CONNECTED_DEVICE".
- **`category`** is required on ad sets — must be a valid `ADV_X_Y` code from `GET /ad_categories`.
- **`call_to_action`** uses field `key` (not `type`) and `clickthrough_url` (not `url`).
- **`companion_asset_id`** is required for AUDIO format ads.
- **Array query params** use repeated parameter names (`&fields=X&fields=Y`), not comma-separated.
- **Report field name** is `fields`, not `report_fields`.
- **No DELETE** on campaigns/ad sets/ads — use status changes (ARCHIVED, PAUSED).
- **Base URLs**: sandbox is `ads-sandbox/v3`, production is `ads/v3`, both under `api-partner.spotify.com`.

## OpenAPI Spec

- `external-v3.yaml` — Public OpenAPI v3 spec (~8.6K lines), committed to repo.

## Execution Pattern

All skills follow the same pattern: read settings file -> determine base URL from environment -> construct curl command -> if `auto_execute` is false, show curl and confirm before executing -> format and display response. This pattern is duplicated across skills rather than abstracted, so changes to the execution flow must be applied to each skill individually.
