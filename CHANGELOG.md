# Changelog

## [1.10.0] - 2026-11-17

### Added
- Spotify Ads language standards in `skills/api-reference/references/language-standards.md`: hard limits, how to word a confirmation, when to act or ask a clarifying question, scope and voice, terms, enum display names, money, number, and date formats by locale, benchmarks, output patterns for success, errors, rejections, and empty states, banned words and punctuation, length limits, and non-English output. Every skill and the request-builder agent now read it before sending any output to a user.
- A Confirmation section in `skills/api-reference/references/api-behaviors.md`, the single source for which actions need a confirmation, keyed to `auto_execute`. Pausing and resuming delivery both need one.
- `scripts/api-request.sh` now checks every request against the workflow's OpenAPI document before sending it. The check covers query parameters and the JSON body at every depth. Missing or null required fields, missing required query parameters, bodies, and `oneOf` discriminators, wrong types, length, range, and item-count bounds, read-only fields, and invalid JSON block the request. It exits with status 3, prints `ERROR: Request not sent.` with one line per problem, and never reaches the API. Fields, query parameters, and enum or discriminator values the spec does not define only warn. The request is sent and `WARNING: Sent anyway` lists each one, with a "did you mean" suggestion where one fits. A local block could reject a request the user explicitly asked for, so these are reported rather than blocked. The check fails open, sending as before, when no document has been fetched, Python is missing, or the operation is not in the public spec, which prints a warning.
- `scripts/openapi-op.sh describe <METHOD> <path>` prints a compact view of one operation, with `$ref`s resolved, `allOf` merged, `oneOf` branches labelled, required fields marked, read-only fields hidden, and the spec's common-mistake hints shown inline. `openapi-op.sh search <words>` ranks operations by relevance. `live-openapi.md` now tells agents to use it instead of reading the 400 KB YAML
- `scripts/openapi_tool.py`, a standard-library-only OpenAPI loader, describer, searcher, and validator. It needs no new dependencies
- `tests/test-openapi-tool.sh` with offline assertions for the loader, describer, searcher, and pre-send validation (151 as of this release). Setting `OPENAPI_TOOL_LIVE_SPEC` also checks that the published spec parses the same as with Ruby's YAML
- An eval suite in `evals/`, run with `claude plugin eval`: smoke cases for lookups and easy edits, resolving from context and safe guesses, confirmations, refusals, and enum display names; safety scenarios for draft publish and delete, bulk budget changes, member removal, and denied direct writes; language cases checked against the language standards; shared graders; and `evals/run-in-docker.sh`, a Linux container runner for cases that need Bash. No case calls the Ads API or needs Ads API credentials
- Replay and record modes in `scripts/api-request.sh` for evals. When `EVAL_ADS_API_FIXTURES` is set, the wrapper answers from fixture files keyed by method and normalized path instead of calling the API, and logs each request so graders can check what was sent; `fetch-openapi-schema.sh` serves a saved schema snapshot. `EVAL_ADS_API_RECORD` saves real responses as fixtures and refuses anything but GET unless writes are explicitly allowed. Neither mode affects normal requests
- `tests/test-audience-estimates.sh`, which checks that every audience estimate example in skills and agents includes `bid_micro_amount`, including for `AUTOBID`. `tests/test-openapi-tool.sh` also checks that `api-request.sh` blocks an estimate with a missing or null bid before sending it
- `tests/test-api-reference-files.sh`, which checks that the removed static API reference copies stay removed and that reference links resolve

### Changed
- `README.md` and `CONTRIBUTING.md` now match current behavior. The README lists the `drafts` skill, the auto-loaded API reference, and the request-builder agent. It also covers bulk pause and resume as confirmed live changes, which confirmations `auto_execute` does not skip, the `environment` setting, and a new "How requests are made" section on the live OpenAPI download, pre-send checks, `Idempotency-Key`, and attribution headers. Its troubleshooting entries now use the messages the plugin actually prints, and it gives accurate Windows Python Store-stub guidance and a Development section. `CONTRIBUTING.md` now documents the offline regression suites and evals instead of saying there is no automated test suite
- `ANTIGRAVITY.md` now lists every skill, including `drafts`, `campaign-strategy`, `media-plan-to-draft`, `audiences`, `measurement-setup`, `measurement-debug`, `account-admin`, and `change-history`, and the auto-loaded API reference. It also has new sections on the draft-first write workflow and the live API contract. Both sections point to `api-behaviors.md` and `live-openapi.md` instead of repeating their rules
- `scripts/fetch-openapi-schema.sh` records where it saved the document, so later shells, which do not inherit `OPENAPI_FILE`, can find it for validation and `openapi-op.sh`. A recorded document is used for up to 6 hours
- Synced version `1.10.0` across the Claude Code, Codex, and Antigravity manifests
- Runtime behavior the spec cannot express now lives in `skills/api-reference/references/api-behaviors.md`. It covers micro-amounts, the Reserved Pricing and Forecasting flow, estimates, geo lookup, reporting quirks, draft VALIDATE/PUBLISH semantics, live entity lifecycle, and error handling and retry safety. `build-campaign`, `ads`, `drafts`, `campaign-strategy`, its planning framework, the request-builder agent, `api-reference`, and `AGENTS.md` now point to it
- Audience estimates no longer rely on a static note saying `bid_micro_amount` is required. The general rule applies instead: include every field the live spec marks as required, and the AUTOBID no-bid exception applies only to ad set payloads
- `media-plan-to-draft` now reads and follows `live-openapi.md` before its first Ads API v3 call, matching the other skills
- `api-reference`, `build-campaign`, `ads`, `drafts`, and the request-builder agent now list a few critical rules inline, so agents see them without opening `api-behaviors.md`: send only spec-defined fields and every required one, including fields whose description says required; set `placements` when creating an ad set and on every estimate from catalog-allowed values, and keep it valid on ad set updates; never resend a 4xx-rejected body unchanged; and refetch `draft_hierarchy_version` before VALIDATE/PUBLISH

### Fixed
- `scripts/api-request.sh` and `hooks/check-token.sh` now detect Claude Code from `CLAUDECODE=1`. Claude Code sets `CLAUDE_PROJECT_DIR` only for hooks, not in the Bash tool shell where skills run `api()`, so Claude Code requests were detected as Antigravity: they sent `X-Spotify-Ads-Sdk: antigravity-cli-plugin/<version>` and looked for settings in `.agents` first. Codex is now detected from `CODEX_THREAD_ID` or `CODEX_SESSION_ID`, which Codex exports to its shell; it never exports `CODEX_PROJECT_DIR`, so Codex requests were also reported as Antigravity. An explicit `CLAUDE_PROJECT_DIR` or `CODEX_PROJECT_DIR` still wins over these markers, which a nested agent can inherit. SDK usage recorded as `antigravity-cli-plugin` before this fix includes Claude Code and Codex traffic
- The Codex PreToolUse hook now runs as Codex. Codex passes no `CODEX_*` variable to hook processes, so the hook was detected as Antigravity: it skipped token and attribution header rewrites for hand-written `curl` and replied in Antigravity's format. It now recognizes Codex by the `turn_id` in the hook payload. The hook command is unchanged, so existing Codex installs keep their approved hook
- `bulk` and `drafts` no longer keep going after a draft create fails. They skip every step that depends on the failed draft (patches, draft ads, reads, and VALIDATE) instead of sending requests that can only fail. On the API's "maximum number of ad set drafts" 400, they stop work for that campaign without retrying, report which targets were staged and skipped, list the campaign's drafts, and offer to publish or delete stale ones. Bulk draft creates are split or preceded by cleanup when they would exceed the limit
- `bulk`, `drafts`, and `build-campaign` now choose start times well clear of the minimum lead time stated in the live ad product catalog's `start_time` constraint text, and recheck staged ad set start times against it right before VALIDATE and PUBLISH. If one falls short, they propose a later time or ask whether the exact time matters, rather than failing validation with `INVALID.AD_SET.START_TIME_TOO_CLOSE`. The rule is recorded in `api-behaviors.md`
- `api-reference`, `campaigns`, `ads`, `drafts`, `bulk`, `monitor`, `dashboard`, `export`, `clone`, and the request-builder agent now state three easy-to-miss rules: only campaigns have a `PAUSED` status (ad sets and ads pause through `delivery: OFF`, and paused ad sets are found via the read-only `is_paused` field); a campaign's ad sets are listed with `ad_sets?campaign_ids=`, not a nested `/campaigns/{id}/ad_sets` route; and updates use PATCH, never PUT
- `bulk` pause, resume, and delivery for ad sets and ads no longer stage `status: PAUSED` or `delivery` on drafts, which the draft schemas do not accept. They now send a confirmed live `delivery` PATCH, resume now lists ad sets with `delivery=OFF` and reports account-level pauses separately instead of trying to resume them, and resume and archive no longer filter ad sets with `statuses=PAUSED`
- `monitor`, `clone`, `bulk`, and `api-reference` no longer list ads with `campaign_ids`, which the ad list endpoint does not accept. They list a campaign's ad sets first and pass repeated `ad_set_ids`
- "Min audience threshold was not met" guidance in `AGENTS.md`, `build-campaign`, `ads`, `clone`, the request-builder agent, and the full campaign flow example no longer suggests retrying or silently widening targeting. Agents now report the narrow audience, suggest broader options along with any `bid_suggestion`, and re-estimate with the targeting the user chooses. "Proceed anyway" is offered only when the estimate came back valid but low, never after a threshold 400
- The draft VALIDATE/PUBLISH response shape in `AGENTS.md`, `drafts`, the static API references (since removed), the full campaign flow example, and `tests/test-scenarios.md` now matches the API: 200 means success, hierarchy validation errors return 400 with a `PublishCampaignResult` carrying `validation_errors`. On a 400, agents check for `validation_errors` first and never retry automatically
- Audience estimate guidance in `AGENTS.md`, the static API references (since removed), `ads`, `build-campaign`, `drafts`, and the request-builder agent no longer claims `AUTOBID` estimates can omit `bid_micro_amount` (the server returns 400 `bidMicroAmount must not be null`). The AUTOBID no-bid exception now applies only to ad set payloads. `campaign-strategy` no longer hard-codes the estimate required-field lists and relies on the live spec instead
- `scripts/api-request.sh` now replaces `{ad_account_id}` in the request body as well as the path. Agents that wrote the placeholder into an estimate body sent it literally and got a 400
- `drafts` now runs an audience estimate for each draft ad set before creating it, using the same rules as `build-campaign`
- `live-openapi.md` and `AGENTS.md` now state general rules: every request payload must include every field the live spec marks as required, including nested and array-item fields, for every endpoint; only fields the spec defines may be sent; and docs must not name fields the public spec does not define
- The token-refresh hook now refreshes expired tokens for calls made through the skills' `api()` wrapper. Those commands name neither the API host nor `$BASE_URL`, so the hook did not recognize them and let them run with an expired token. When a refresh fails, the hook's message now includes the refresh helper's last diagnostic line (never a token value)
- `report` now lists the only reporting endpoints that exist and tells agents not to invent others. It keeps `metrics`, `dimensions`, and `campaign_ids` out of GET report query strings, requires `report_end` as well as `report_start` for DAY granularity, and takes `statuses` and `insight_dimension` values from the live spec enums instead of hard-coded lists. It also checks that date variables are set before building an async report body, since an unset variable produced `"T00:00:00Z"` and a 400. `ads` and `build-campaign` gained estimate payload checks covering required fields and `budget.currency`

### Removed
- Static API reference files `skills/api-reference/references/endpoints.md`, `schemas.md`, and `enums.md`. They duplicated the live OpenAPI document and drifted from it. Field lists, types, required flags, and enum values now come only from the live spec via `live-openapi.md`

## [1.9.0] - 2026-10-01

### Added
- Authorization Code with PKCE (`S256`) using team-owned client IDs, cryptographic verifier and state generation, exact loopback callback validation, and a printed-URL browser fallback
- Media-plan-to-draft orchestration for spreadsheet, document, presentation, PDF, and text plans, with source provenance, reconciliation, live Ads API enrichment and forecasts, explicit completeness states, a strict review gate, and handoff to the existing draft workflow without publishing
- Windows and Linux support: Python is detected as `python3`, `python`, or `py`, and asset uploads use portable `stat` and temporary-directory handling
- Live public OpenAPI contract checks via `scripts/fetch-openapi-schema.sh`. Each workflow fetches the current Ads API v3 document once, inspects every planned operation's parameters and request body, and stops before any API call if the document cannot be retrieved or recognised
- Deterministic `Idempotency-Key` on supported create requests in `scripts/api-request.sh`, derived from a SHA-256 hash of the canonical request (`scripts/canonical-hash.py`), so a retried create is recognised by the server instead of duplicated. `--no-dedup-key` opts out
- Reserved buying guidance that fetches the fixed Reserved rate before an audience forecast, uses it as `bid_micro_amount`, and reports it separately from forecast CPM and bid suggestions
- Create retry-safety reference in `skills/api-reference/references/create-retry-safety.md`
- Skill and SDK attribution enforcement in the `PreToolUse` hook, as `hooks/lib/attribution.sh` sourced by `hooks/check-token.sh`. Raw curl calls that skip the request wrapper are rewritten to carry `X-Spotify-Ads-Skill` and `X-Spotify-Ads-Sdk`, so per-skill usage and error-rate reporting is no longer blind to ad-hoc traffic. Attribution is a sourced library rather than a second hook on purpose: matching `PreToolUse` hooks run in parallel against the original input and the last rewrite wins, so a separate hook would race the token refresh and drop one of the two edits
- Best-effort skill inference from the session transcript, scanning the most recent lines newest-first and accepting only names matching a real skill in this plugin. Inferred values carry an `-inferred` suffix so reporting can separate them from the wrapper's deterministic value
- `SPOTIFY_ADS_SKILL_LOOKBACK_LINES` to tune how far back skill inference looks, defaulting to 300 transcript lines
- `SPOTIFY_ADS_ATTRIBUTION_LIB` to point the hook and its tests at an alternative attribution library, so a deliberately broken copy can be tested without editing the installed one
- `SKILL_HEADER` to the output of `api-request.sh --env`, so raw-curl call sites no longer construct the skill attribution header by hand
- Unit and shell regressions for PKCE construction, callback validation, token refresh rotation, legacy migration, direct-token behavior, and forbidden secret-based runtime paths
- `tests/test-api-request.sh`, covering `--env` output quoting, `SKILL_HEADER` scoping, and values containing shell metacharacters
- `tests/test-openapi-fetch.sh` and `tests/test-marketplace-metadata.sh`, covering OpenAPI document retrieval and marketplace names, sources, policies, and manifest version alignment
- 52 attribution assertions in `tests/test-check-token.sh`, covering detection, curl-injection edge cases, inference ordering, and per-platform behaviour

### Changed
- Replaced application-secret and HTTP Basic token exchanges with public-client authorization and refresh requests containing `client_id`
- Added the explicit `auth_flow` settings marker and cross-platform automatic PKCE refresh without a platform credential store
- Kept legacy access tokens usable until expiry while requiring one-time PKCE reauthorization for future refreshes
- Updated setup documentation to separate team application registration from individual authorization and explain client-level attribution and rate-limit isolation
- Refined ad product catalog validation to check final creates and deep-merged effective updates, including the parent and runtime context they depend on
- Renamed the API reference skill to `spotify-ads-api-reference` to meet Agent Skills naming rules
- The hook now recognises Spotify Ads API calls written as `$BASE_URL/...`, not just those naming `api-partner.spotify.com` literally. The assets and audiences upload flows use the variable form and previously bypassed the hook entirely, missing both token refresh and attribution
- Antigravity gets a warning rather than a rewrite when attribution is missing, because its `PreToolUse` contract supports allow and deny decisions only and cannot modify a tool call on any of its hook events
- Documented marketplace installation through the Claude and Codex apps
- `AGENTS.md` is now the only project instruction file; the `CLAUDE.md` shim was removed because Claude Code 2.1.277 and later read `AGENTS.md` directly
- Synced version `1.9.0` across the Claude Code, Codex, and Antigravity manifests

### Fixed
- Resolved the Codex `PreToolUse` hook from the installed `${PLUGIN_ROOT}` instead of falling back to the workspace directory when `CODEX_PLUGIN_ROOT` is unset
- Prevented initial OAuth tokens from entering captured helper stdout by writing settings directly through an atomic mode-0600 file replacement
- Replaced post-write permission changes with secure-at-creation settings files and a private pending-token handoff for managed workspaces that require separate settings-write approval
- Replaced the undefined direct-token environment-variable handoff with a non-echoing terminal prompt, keeping bearer tokens out of chat and generated command arguments
- Kept refresh tokens out of process arguments by passing them to the automatic refresh helper through stdin
- Pixel discovery failed for every request because `GET /businesses/{id}/pixels` returns 403; it now lists `GET /businesses/{id}/datasets` and inspects each dataset's `pixel` field
- `eval $(api --env)` silently set nothing. The printed values were unquoted, so the space inside `SDK_HEADER` split the assignment and every line became a prefix assignment to a nonexistent command. Raw-curl paths that follow the documented flow, including asset and audience uploads, were therefore sending an empty `Authorization` header along with empty tracking headers. All values are now single-quoted, with embedded single quotes escaped
- Removed the obsolete root `settings.json`, whose object-valued `agent` field caused Claude's UI marketplace sync to reject the plugin with `plugin_upload_settings_invalid`; tool permissions remain defined in the skill and agent frontmatter

### Removed
- Application-secret collection, macOS Keychain access, secret-dependent refresh, and the shell-based manual OAuth flow
- The bundled OpenAPI specification, superseded by the live public document

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
