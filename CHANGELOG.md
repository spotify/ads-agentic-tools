# Changelog

## [1.8.0] - 2026-08-13

### Added
- Audience management for customer-list uploads and replacements, web-event and ad-engagement audiences, lookalikes, discovery, editing, status checks, and deletion
- Conversion measurement setup for Spotify Pixel, Conversions API (CAPI), datasets, advanced matching, event mapping, mobile apps, and ad-account sharing
- Read-only-first measurement debugging for missing, stale, duplicated, misrouted, or unattributed Pixel and CAPI events
- Business and ad-account administration for account discovery, member and role audits, invitations, access assignments, and supported account updates
- Change-history queries for auditing who changed campaigns, ad sets, creatives, budgets, targeting, statuses, and other settings within the API's 180-day retention window
- A prompt catalog and expanded behavioral scenarios covering routing, schema rules, destructive-operation confirmation, draft workflows, and recovery behavior
- A 36-case shell regression suite for token updates, command substitution, settings discovery, and hook response formats

### Changed
- Made drafts the default for campaign, ad-set, and ad creation or modification; complete hierarchies are validated before publishing, and publishing always requires explicit confirmation
- Added staged edits for published entities, including existing-draft preservation, create-from-published flows, parent-campaign resolution, and grouped validation for bulk changes
- Updated the bundled OpenAPI specification and API reference to the August 2026 Ads API surface
- Replaced deprecated `objective` usage on draft campaigns with `delivery_goal_group` and documented goal-to-group mappings; direct v3 campaign creation and estimate requests retain `objective` where the API still requires it
- Removed unsupported `dma_ids` targeting guidance while retaining an explanation that DMA results may still appear in geo lookup responses
- Updated budget and bid documentation for ad accounts in any billing currency instead of assuming USD
- Documented draft-only field optionality, `FAILED` ad and async-report statuses, experiment availability, and attribution-window fields
- Clarified that `AUTOBID` enables automatic bidding without `bid_micro_amount`, while `UNSET` should not be chosen for new ad sets
- Refreshed natural-language routing, plugin prompts, onboarding instructions, marketplace descriptions, README examples, and Claude Code auto-update guidance
- Synced version `1.8.0` across the Claude Code, Codex, and Antigravity manifests

### Fixed
- Prevented OAuth token values containing pipes, ampersands, backslashes, wildcard characters, or other shell metacharacters from corrupting settings or command substitution
- Prevented ordinary update requests from writing directly to published campaign hierarchies when they should be staged as drafts
- Prevented direct-write permission errors from being reported as proof that credentials are entirely read-only
- Corrected draft campaign examples and manual reference schemas that still used deprecated or invalid campaign-goal values
- Aligned request-builder bidding guidance with the current `AUTOBID` and `UNSET` semantics

## [1.7.0] - 2026-07-23

### Added
- Antigravity CLI and Antigravity 2.0 support, including the root `plugin.json` manifest, `ANTIGRAVITY.md` context file, auto-discovered root `hooks.json`, and `.agents/spotify-ads-api.local.md` settings path
- Shared `scripts/api-request.sh` request wrapper for settings discovery, authentication, ad account substitution, HTTP status capture, and deterministic SDK and skill telemetry headers
- `X-Spotify-Ads-Skill` attribution on every Spotify Ads API request across all skills and the request-builder agent, enabling per-skill invocation and error-rate reporting
- Complete third-party tracking event documentation, including impression, click, quartile, completion, and viewability trackers
- Campaign-level audience insight reports in addition to ad-set insights
- Explicit handling guidance for insight-report 422 responses caused by insufficient impressions, reach, or listeners
- Optional ad-level `start_time` and `end_time` schedule overrides in the API reference

### Changed
- Replaced Gemini CLI integration with Antigravity: `gemini-extension.json` became `plugin.json`, `GEMINI.md` became `ANTIGRAVITY.md`, `.gemini/` settings moved to `.agents/`, and the SDK product identifier changed to `antigravity-cli-plugin`
- Replaced duplicated settings and curl boilerplate across all 14 skills and the request-builder agent with the shared API request wrapper
- Migrated Antigravity token refresh from Gemini's `BeforeTool` contract to Antigravity's `PreToolUse` contract and documented its allow/deny behavior
- Moved Claude and Codex hook declarations into their platform manifest directories and gave Codex a dedicated hook config, preventing cross-platform hook auto-discovery and marketplace installation failures introduced before 1.6.1
- Increased the documented maximum number of frequency caps per ad set from 3 to 6
- Updated insight reporting to accept exactly one campaign or ad-set ID and require the matching `entity_ids_type` and `entity_status_type`
- Updated the bundled OpenAPI spec and reference schemas with explicit object types, nullable ad scheduling fields, a 512-character Android app URL limit, and current draft request definitions
- Synced the 1.7.0 version across the Claude Code, Codex, and Antigravity manifests

### Fixed
- Corrected third-party tracking payloads to use `measurement_event` instead of `type`; examples now set `IMPRESSION` and `CLICKED` explicitly so click trackers are not silently treated as impression trackers
- Prevented malformed or duplicated `X-Spotify-Ads-Sdk` and `X-Spotify-Ads-Skill` headers by constructing them centrally in the request wrapper
- Fixed `--env` passthrough when skills invoke the request wrapper through their local `api` helper
- Fixed Antigravity hook discovery and output formatting for both Antigravity CLI and Antigravity 2.0
- Fixed token-refresh path resolution for installed Claude Code, Codex, and Antigravity plugins
- Clarified that insight reports should be polled no more than daily after insufficient-data responses and abandoned roughly two weeks after an ad flight ends

### Removed
- Gemini CLI extension support and its `gemini-extension.json`, `GEMINI.md`, `.gemini/` settings path, and `hooks/gemini-hooks.json` integration
- The deprecated `restricted_ad_category` field from draft campaign request documentation

## [1.5.0] - 2026-06-10

### Added
- Gemini CLI extension support: root `gemini-extension.json` manifest, `GEMINI.md` context file, and a `/configure` custom command; skills load through Gemini's native Agent Skills support with no content duplication
- OAuth token auto-refresh on Gemini CLI via a `BeforeTool` hook; hook configs are split per platform (`hooks/gemini-hooks.json` for Gemini, `.claude-plugin/hooks.json` for Claude, `.codex-plugin/hooks.json` for Codex) since each platform rejects the other's event names
- `.gemini/spotify-ads-api.local.md` settings path (gitignored)

### Changed
- Settings lookup is now a three-way fallback across `.codex/`, `.claude/`, and `.gemini/` in all skills, the agent, and the token-refresh hook
- `check-token.sh` detects the platform from the hook payload's `hook_event_name` and emits Gemini's `tool_input` output schema when rewriting commands
- SDK tracking header gains a third product: `gemini-cli-extension/$PLUGIN_VERSION` on Gemini
- Plugin version is now synced across three manifests (`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`, `gemini-extension.json`), all bumped to 1.5.0

## [1.4.0] - 2026-05-20

### Added
- Updated the bundled Spotify Ads API v3 OpenAPI spec and regenerated reference docs from the latest API surface
- Added documentation for `GET /aggregate_reports/totals` to pull deduplicated reach and frequency across campaign, ad set, or ad IDs
- Added current campaign objectives: `PODCAST_STREAMS`, `APP_INSTALLS`, and `WEBSITE_VISITS`
- Added current ad set options including `CATALOG` asset format and `AUTOBID` bid strategy
- Added async report support for optional `insight_dimension` breakdowns with LIFETIME granularity

### Changed
- Updated campaign strategy, build, clone, and ad set guidance to reflect the latest objective, bidding, and format compatibility rules
- Clarified aggregate report `SPEND` handling: returned values are already in account currency and should not be divided by 1,000,000
- Backfilled changelog entries for prior 1.2.0 and 1.3.0 releases
- Bumped Codex and Claude plugin manifests to version 1.4.0

### Fixed
- Fixed insight report guidance so `CITY` and the other current `InsightDimensionType` values are treated as valid breakdowns
- Fixed insight report examples to omit unsupported fields such as `SPEND` and include the required `entity_ids_type=AD_SET`
- Removed stale campaign fields from reference docs where the latest API spec no longer supports them

## [1.3.0] - 2026-05-15

### Added
- Codex plugin support alongside Claude Code, including Codex marketplace metadata
- New workflow skills: campaign strategy, campaign health monitoring, CSV export, bulk operations, and cloning
- `AGENTS.md` as the canonical repository instruction file

### Changed
- Updated README installation docs for the `spotify/ads-agentic-tools` marketplace flow
- Renamed repo metadata from `ads-claude-plugin` to `ads-agentic-tools`
- Standardized settings lookup and SDK tracking headers across Codex and Claude Code
- Expanded API reference docs for targeting quirks, estimate endpoints, and reporting examples

### Fixed
- Fixed malformed curl examples where status-code capture was missing a following space
- Fixed token refresh hook compatibility with Codex and Claude plugin environment variables
- Fixed agent YAML/frontmatter validation and marketplace manifest compatibility

## [1.2.0] - 2026-04-01

### Added
- HTTP status code capture to Spotify Ads API curl commands so success and failure handling is explicit
- Business ad account endpoint documentation for `GET /businesses/{business_id}/ad_accounts`
- Ad account discovery guidance for onboarding through `GET /businesses` followed by `GET /businesses/{business_id}/ad_accounts`

### Changed
- Updated configure flows to discover ad accounts through businesses instead of relying on a non-existent `GET /ad_accounts` list endpoint
- Updated skills and examples to check the appended `HTTP_STATUS:` line before interpreting response bodies
- Clarified retry safety for POST and PATCH requests to avoid duplicate non-idempotent API calls
- Bumped plugin manifests to version 1.2.0

## [1.1.0] - 2026-03-01

### Added
- Asset management skill: upload, list, get, archive creative assets
- Pre-flight audience validation before ad set creation
- Campaign dashboard skill with performance overview and pacing


## [1.0.0] - 2026-03-01

### Added
- OAuth 2.0 authorization flow with automatic token refresh
- Script-based OAuth (Python) with manual browser fallback
- Token refresh hook for automatic re-authentication
- Test harness with 10 validated scenarios
- CHANGELOG.md
- settings.json for plugin default settings

### Changed
- Migrated commands/ to skills/ (agentskills.io standard)
- Bumped version to 1.0.0 for stable public release
- Expanded README for marketplace users
- Improved plugin.json metadata
- Updated settings template with OAuth fields

### Removed
- Internal API spec references from CLAUDE.md
- commands/ directory (replaced by skills/)
