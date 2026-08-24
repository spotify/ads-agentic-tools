# Repository Instructions

This is the canonical instruction file for agents working in this repository. Codex reads `AGENTS.md` directly; Claude Code keeps `CLAUDE.md` as a compatibility shim that points back here.

## What This Is

A Codex, Claude Code, and Antigravity CLI plugin package for the Spotify Ads API v3. Plugin source is markdown and shell; there is no compiled code, package manager, or build step. Lightweight shell regression tests live under `tests/`. The plugin translates natural language into REST API calls for managing campaigns, ad sets, ads, assets, audiences, and reporting.

## Architecture

The plugin follows the agent plugin structure with four component types:

- **Skills** (`skills/`) — User-invokable slash commands and reference documentation, each in its own directory with a `SKILL.md` file:
  - `skills/configure/` — OAuth 2.0 setup with automated and manual flows, plus helper scripts in `scripts/`
  - `skills/campaigns/` — Campaign CRUD operations
  - `skills/ads/` — Ad set and ad management
  - `skills/build-campaign/` — Full campaign builder from natural language descriptions (prefers draft flow)
  - `skills/drafts/` — Draft campaign lifecycle: create, edit, validate, and publish draft campaigns, ad sets, and ads. **Preferred flow** for creating new campaigns — builds the full hierarchy as drafts, validates everything at once, then publishes only after review.
  - `skills/report/` — Aggregate, insight, and async CSV reporting
  - `skills/assets/` — Upload, list, and manage creative assets (audio, video, images)
  - `skills/audiences/` — Customer-list uploads and custom, engagement, event, and lookalike audiences
  - `skills/measurement-setup/` — Pixel, CAPI, datasets, event planning, advanced matching, mobile apps, and sharing
  - `skills/measurement-debug/` — Read-only-first Pixel, CAPI, dataset, deduplication, and attribution troubleshooting
  - `skills/account-admin/` — Business/ad-account discovery and account membership, roles, invitations, and details
  - `skills/dashboard/` — Quick performance overview with pacing for active campaigns
  - `skills/monitor/` — Campaign health diagnostics for pacing, delivery, stalled entities, and underdelivery
  - `skills/export/` — Denormalized CSV exports of campaigns, ad sets, ads, targeting, budgets, and optional metrics
  - `skills/bulk/` — Batch pause, resume, budget, delivery, archive, and creative-swap workflows
  - `skills/clone/` — Clone campaigns or ad sets by reading the source hierarchy and recreating entities with modifications
  - `skills/change-history/` — View a timeline of changes made to campaigns, ad sets, creatives, and other entities. Supports filtering by entity type, actor, change category, and date range (180-day retention).
  - `skills/api-reference/` — Comprehensive API v3 reference documentation with `references/` (endpoints, schemas, enums) and `examples/` (full flows). Activates automatically when the Spotify Ads API is mentioned.
- **Agent** (`agents/spotify-ads-request-builder.md`) — A natural language agent that triggers automatically when users describe advertising tasks conversationally. Handles multi-step operations (campaign -> ad set -> ad) by chaining API calls and passing IDs between steps.
- **Scripts** (`scripts/`) — Shared shell scripts used by skills and agents:
  - `scripts/api-request.sh` — Request wrapper that handles settings discovery, authentication, SDK/skill tracking headers, and curl execution. Skills define a local `api()` function that delegates to this script: `api() { "$PLUGIN_ROOT/scripts/api-request.sh" <skill-name> "$@"; }`. Usage: `api <METHOD> <path> [json_body]` or `api --env` for settings. Paths use `{ad_account_id}` as a placeholder (auto-substituted from settings).
  - `scripts/fetch-openapi-schema.sh` — Downloads the current public Ads API v3 OpenAPI document to a caller-provided temporary path and rejects failed or structurally invalid responses.
- **Hooks** — Per-platform hook configs invoking `hooks/check-token.sh` to automatically refresh expired OAuth tokens before Spotify API calls. `hooks.json` at the plugin root contains the Antigravity `PreToolUse` event, auto-discovered by both Antigravity CLI (`agy plugin install`) and Antigravity 2.0 (`.agents/plugins/` workspace discovery). `.claude-plugin/hooks.json` and `.codex-plugin/hooks.json` contain the Claude/Codex `PreToolUse` event, declared via the `hooks` field in each platform's `plugin.json`. Note: the hook payload and response formats differ across platforms — Claude/Codex use `.tool_input.command` and support command rewriting via `updatedInput`, while Antigravity uses `.toolCall.args.CommandLine` and only supports allow/deny with `decision`/`reason` (the hook refreshes the token in the settings file and tells the agent to re-read it).
- **Commands** (`commands/configure.toml`) — An Antigravity CLI custom command exposing `/configure` as an explicit entry point to the configure skill. Other skills auto-activate on Antigravity via its native Agent Skills support.
- **Settings** (`.codex/spotify-ads-api.local.md`, `.claude/spotify-ads-api.local.md`, or `.agents/spotify-ads-api.local.md`, with each platform preferring its own file and falling back to the other two) — Per-user local config with YAML frontmatter storing OAuth credentials (access_token, refresh_token, client_id, token_expires_at), ad_account_id, and auto_execute. The client_secret is stored in the macOS Keychain (service: `spotify-ads-api-client-secret`, account: `spotify-ads-api`), not in this file. Template lives in `templates/settings-template.md`. These files are gitignored.

## Marketplace Compatibility

Keep both marketplace files intentional and in sync:

- `.agents/plugins/marketplace.json` is the Codex-facing catalog used by `codex plugin marketplace add spotify/ads-agentic-tools`. It must include Codex's `interface.displayName`, `policy.installation`, `policy.authentication`, and `category` metadata. Because this plugin lives at the repository root, use a Git-backed root plugin source (`"source": "url"` with the repository URL) instead of a local `source.path` of `"./"`; Codex treats that local root path as empty and skips the plugin.
- `.claude-plugin/marketplace.json` is the Claude Code-compatible catalog. Claude Code requires marketplace metadata at that path and requires a top-level `owner`. To keep the file portable, use the stricter Claude-valid schema: local plugin sources should use the relative string form (`"source": "./"` for this repo-root plugin), and Codex-only marketplace fields such as top-level `interface` or plugin `policy` should not be added to this file. The Claude plugin manifest `.claude-plugin/plugin.json` must also avoid Codex-only manifest fields such as `interface`; keep display metadata in `.codex-plugin/plugin.json` and the Codex marketplace.

- Antigravity has no marketplace file. The root `plugin.json` is the Antigravity manifest; Antigravity CLI installs via `agy plugin install <repo-url>` and Antigravity 2.0 discovers plugins placed in `.agents/plugins/` (workspace) or `~/.gemini/config/plugins/` (global). Both versions auto-discover `skills/`, `commands/`, and `hooks.json` at the plugin root. Keep `name`, `version`, and `description` in sync with the other two manifests, and do not add Antigravity-only fields (such as `contextFileName`) to the Claude or Codex manifests.

When updating marketplace metadata, keep the plugin name, source path, category, description, and user-facing display name aligned wherever each schema supports those fields. The plugin `version` must be bumped in all three manifests together: `.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, and `plugin.json`.

## API Conventions to Know

These non-obvious API quirks were discovered through real testing and are critical when modifying any command or agent:

- **Micro-amounts**: Budget and bid values in entity payloads (`budget.micro_amount`, `bid_micro_amount`) are in micro-units (1 unit of the ad account's billing currency = 1,000,000 micro-units; e.g., $1 USD = 1,000,000, ¥1 JPY = 1,000,000). However, SPEND values returned by `aggregate_reports` are already in the billing currency — do NOT divide those by 1,000,000.
- **`bid_strategy`** is a plain string enum (`MAX_BID`, `COST_PER_RESULT`, `AUTOBID`, `UNSET`), not an object. Default to `MAX_BID` with a required `bid_micro_amount`; use `AUTOBID` for automatic bidding without `bid_micro_amount`. Do not choose `UNSET` for new ad sets.
- **`geo_targets`** is a flat object (not an array) with a required `country_code` and optional refinement arrays (`region_ids`, `city_ids`, `postal_code_ids`). Use `GET /targets/geos?country_code=<code>&q=<query>` to look up geo IDs. Geo types returned by lookup: `REGION` (states/provinces), `DMA_REGION` (media markets), `CITY`, `POSTAL_CODE` — note that `dma_ids` is no longer a valid targeting field; DMA-level targeting is not supported. Example: `{"country_code": "US", "region_ids": ["4831725"]}` targets Connecticut. NEVER fall back to country-only without looking up the user's requested location first.
- **`platforms`** valid values are `ANDROID`, `DESKTOP`, `IOS` — not "MOBILE" or "CONNECTED_DEVICE".
- **`category`** is required on ad sets — must be a valid `ADV_X_Y` code from `GET /ad_categories`.
- **`call_to_action`** uses field `key` (not `type`) and `clickthrough_url` (not `url`).
- **`companion_asset_id`** is required for AUDIO format ads.
- **Array query params** use repeated parameter names (`&fields=X&fields=Y`), not comma-separated.
- **Report field name** is `fields`, not `report_fields`.
- **No DELETE** on campaigns/ad sets/ads — use status changes (ARCHIVED, PAUSED).
- **Base URL**: `https://api-partner.spotify.com/ads/v3`.
- **Tracking headers**: The request wrapper (`scripts/api-request.sh`) injects `X-Spotify-Ads-Sdk: <sdk-product>/<version>` and `X-Spotify-Ads-Skill: <skill-name>` on every API call. Skills never construct these headers manually — the wrapper reads the plugin version from the platform manifest and takes the skill name as its first argument. This eliminates malformed-header errors seen in production logs (e.g., doubled `X-Spotify-Ads-Sdk: X-Spotify-Ads-Sdk: ...`).
- **`entity_status_type` must match `entity_type`** in `aggregate_reports` queries. For example, use `entity_status_type=AD_SET` when `entity_type=AD_SET` — using `entity_status_type=CAMPAIGN` with `entity_type=AD_SET` causes a filter validation error.
- **Audience estimates**: The build-campaign and ads skills run `POST /estimates/audience` before creating ad sets to validate targeting. This catches "min audience threshold" errors before they happen.
- **Ad product catalog validation**: Before every campaign, ad set, or ad POST/PATCH, follow `skills/api-reference/references/ad-product-validation.md`. Fetch `GET /ad_product_catalog` once per workflow; do not maintain a timed cross-workflow cache because the endpoint returns `Cache-Control: no-cache, no-store`. Validate final creates and deep-merged effective updates, including required parent/runtime context. Never send a known violation, but do not add per-field success checklists or validation-only confirmation gates. Campaign responses do not consistently expose `ad_product`, so use known workflow context and do not silently infer a reserved CONTENT/FPMNG product.

## OpenAPI Spec

- `https://developer.spotify.com/reference/ads-api/v3/api.yaml` is the authoritative OpenAPI v3 document. Before the first Ads API call in every workflow, follow `skills/api-reference/references/live-openapi.md`: fetch it once, inspect every planned operation's parameters and request body, reuse it throughout that workflow, and remove the temporary file afterward.

## Preferred Campaign Creation: Draft → Validate → Publish

When creating new campaigns, prefer the **draft workflow** over direct entity creation:

1. **Create drafts** — `POST /ad_accounts/{id}/drafts/campaigns`, then `POST /ad_accounts/{id}/drafts/ad_sets` (with `campaign_id` = draft campaign ID), then `POST /ad_accounts/{id}/drafts/ads` (with `ad_set_id` = draft ad set ID)
2. **Validate** — `POST /ad_accounts/{id}/drafts/campaigns/{draft_id}` with `{"action": "VALIDATE", "draft_hierarchy_version": N}`. This checks the entire hierarchy at once. On success, returns HTTP 200 with `validation_errors: null`. On failure, returns HTTP 400 with a `validation_errors` array containing entity type, ID, and message for each issue.
3. **Fix and re-validate** — use PATCH on draft entities to fix errors, then validate again
4. **Publish** — `POST /ad_accounts/{id}/drafts/campaigns/{draft_id}` with `{"action": "PUBLISH", "draft_hierarchy_version": N}`. This publishes the drafts as live entities, retaining the same entity IDs.

The draft flow is preferred because validation is batched — all errors across campaigns, ad sets, and ads surface before anything goes live. The direct flow validates per-entity, so errors in ads are only discovered after the campaign and ad sets are already live.

Key draft conventions:
- **`draft_hierarchy_version`** is a read-only field on the draft **campaign** entity only (ad set and ad drafts return it as `null`). It increments when any entity in the hierarchy is created or edited. Always fetch the current version from the draft campaign immediately before publishing or validating; do not reuse a version captured before creating child draft ad sets/ads or applying edits.
- **Publishing requires explicit confirmation** — `PUBLISH` creates live entities, so ask the user to confirm immediately before the publish request even when `auto_execute` is true.
- **Draft entities can be deleted** — `DELETE` on `/drafts/campaigns/{id}`, `/drafts/ad_sets/{id}`, or `/drafts/ads/{id}`. Draft DELETE returns 204 and is safe to retry.
- **Create-from-published** — `POST /ad_accounts/{id}/campaigns/{campaign_id}/drafts` (also for ad sets and ads) creates a draft copy of a live entity for editing. The draft reuses the same entity `id` (not a new UUID) and its status becomes `ACTIVE_RESTRICTED`.

## Execution Pattern

All skills use the request wrapper script (`scripts/api-request.sh`) to make API calls. Each skill defines a local `api()` function:

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" <skill-name> "$@"; }

api GET "ad_accounts/{ad_account_id}/campaigns?limit=50"
api POST "ad_accounts/{ad_account_id}/campaigns" '{"name":"...","objective":"..."}'
```

Before using the wrapper, each workflow fetches the current public OpenAPI document once and uses it to check the complete operation contract as described in `skills/api-reference/references/live-openapi.md`. The wrapper then handles settings discovery (platform-ordered fallback), authentication, SDK/skill tracking headers, and `\nHTTP_STATUS:<code>` capture without downloading the document again for each request. If `auto_execute` is false, the skill presents the command and asks for confirmation before executing. Exceptions (asset file uploads, OAuth token exchange) use raw curl — see the relevant skill for details.

In skills, agents, documentation, and test scenarios, express standard Ads API v3 requests with the shared `api()` helper, never as expanded raw HTTP-client commands. This keeps authentication, tracking headers, settings lookup, and status capture centralized. Only the documented asset-upload and OAuth implementations may use their required raw transport commands; do not use those exceptions as patterns for ordinary API examples.

After execution, check the `HTTP_STATUS:` line first:
- **2xx**: Request succeeded — parse and display the response body.
- **4xx/5xx**: Request failed — display the error from the response body. **Never retry a POST or PATCH that returned a non-timeout 4xx** — the request was received and rejected, not lost.
- **Retry safety**: Only retry on network errors or 5xx responses, and only for idempotent methods (GET). Never automatically retry POST or PATCH — these are non-idempotent and may have already been applied server-side (e.g., a 500 after the entity was created). On POST/PATCH failure, check for the created/modified resource first before suggesting a retry.

## Ad Account Discovery

There is no `GET /ad_accounts` list endpoint. To discover a user's ad accounts during onboarding:
1. `GET /businesses` — lists businesses the authenticated user belongs to
2. `GET /businesses/{business_id}/ad_accounts` — lists ad accounts under a specific business

This two-step flow is used by the configure skill during setup.
