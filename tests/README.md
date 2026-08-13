# Plugin Test Guide

Use this directory for two related jobs:

- [`prompt-catalog.md`](prompt-catalog.md) gives users and internal testers a representative prompt for every plugin capability.
- [`test-scenarios.md`](test-scenarios.md) defines the deeper behavioral checks for API routing, safety, schemas, and multi-step execution.

The prompt catalog is the quickest smoke-test surface. The scenarios are the source of truth when validating a release.

## Prerequisites

1. A Spotify Developer app with Ads API access
2. A Spotify Ads business and ad account suitable for testing
3. Python 3.8+ for the automated OAuth flow, or use the manual flow
4. Codex, Claude Code, or Antigravity with this source checkout installed
5. Test creative files and a synthetic customer-list CSV when exercising uploads

Never use real customer data in plugin tests. Prefix test campaign, ad set, and ad names with `[Test reject]` so test ads are rejected by review and cannot serve.

## Suggested runs

### Read-only smoke test

Run scenarios 1-2, 7, 13-14, 22, 26, 28-29, 31, and 32. These cover configuration plus the major read-only and planning skills without changing campaign or account state.

### Creation and draft workflow

Run scenarios 3-6 and 11-21 sequentially. Several scenarios reuse IDs or assets created by earlier scenarios. Keep the draft used for deletion separate from the draft used for publishing.

### Newer skill coverage

Run scenarios 22-32 to exercise campaign strategy, monitoring, export, bulk operations, cloning, audiences, measurement, account administration, and change history. Scenarios 24-25, 27, and 30 mutate state and require the confirmations described in each scenario.

### Draft-first regression coverage

Run scenarios 33-34 to verify that implicit tracking edits use drafts and that an explicitly requested direct write handles permission denial without overstating the credentials' restrictions. Scenario 33 requires existing published ads with tracking entries; Scenario 34 may use a mocked 403 response.

## Validation checklist

For every scenario, verify:

- [ ] The natural-language prompt routes to the intended skill or workflow.
- [ ] The request wrapper is used for Ads API calls and sends both SDK and skill tracking headers.
- [ ] The API method, path, parameters, and request body match the scenario.
- [ ] The agent checks `HTTP_STATUS:` before interpreting the response.
- [ ] Dates are calculated from the execution date rather than copied from an old example.
- [ ] Tokens, signed URLs, customer data, and CAPI identifiers are not exposed.
- [ ] Read-only prompts do not mutate state.
- [ ] Destructive or externally consequential actions receive explicit confirmation at the required boundary.
- [ ] POST and PATCH requests are not automatically retried after ambiguous failures.
- [ ] Results are summarized clearly, including partial failures in batch workflows.

## Test fixtures

Record fixture IDs outside this repository. Useful fixtures include:

- one live `[Test reject]` campaign hierarchy that can be paused, cloned, and reported on
- two unpublished draft campaigns: one to publish and one to delete
- READY audio and image assets
- a tiny synthetic customer-list CSV containing invented data only
- a Pixel/CAPI/dataset topology with known diagnostics for read-only measurement tests
- a non-owner account member whose access can be inspected; only mutate membership in a dedicated test business

Token-refresh testing requires a valid refresh token and macOS Keychain entry. Set `token_expires_at` to a past timestamp, but never add `client_secret` to a settings file.
