# Changelog

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
