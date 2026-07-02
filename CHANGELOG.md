# Changelog

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
