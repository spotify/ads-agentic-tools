# Changelog

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
