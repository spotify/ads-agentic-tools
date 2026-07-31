---
name: measurement-debug
description: "Diagnose existing Spotify Ads Pixel, Conversions API (CAPI), and dataset implementations when events are missing, stale, duplicated, unexpectedly high or low, not deduplicated, attached to the wrong account, or present in diagnostics but absent from campaign reporting. Use for Pixel/CAPI troubleshooting, event-delivery audits, token/connection mismatches, source comparison, or measurement incident triage. Prefer read-only checks and never create test conversions without explicit confirmation."
---

# Spotify Ads API — Measurement Debug

Find the failing layer before recommending a change. Read [troubleshooting.md](references/troubleshooting.md) before diagnosing.

## Setup

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" measurement-debug "$@"; }
```

Measurement paths use `business_id`. Discover it with `GET businesses` when absent.

## Triage

Capture:

- expected event, expected volume, first/last known good time, timezone, and affected environment
- Pixel, CAPI, or both; direct code, web GTM, server GTM, or another owner
- business, dataset, integration, connection, and ad-account IDs
- whether the problem is **receipt**, **deduplication**, **sharing/selection**, or **attributed reporting**
- a sanitized failing request/response and trace ID when available

Do not ask for CAPI tokens, raw email/phone, cookies, device IDs, IP addresses, or production payloads. Ask for redacted field names and error metadata instead.

## Read-only audit

### 1. Resolve topology

```bash
api GET "businesses/<business_id>/pixels?include_events=true"
api GET "businesses/<business_id>/capi/<capi_connection_id>"
api GET "businesses/<business_id>/capi/<capi_connection_id>/tokens"
api GET "businesses/<business_id>/datasets"
api GET "businesses/<business_id>/datasets/<dataset_id>"
api GET "businesses/<business_id>/ad_accounts/<ad_account_id>/datasets"
```

The `GET datasets` endpoint does not accept `limit` or `offset` parameters. The `GET pixels` endpoint may return 403 for some businesses; if so, check the `pixel` field on individual dataset responses instead.

Verify that:

- the expected integration is in the expected dataset
- the dataset is shared to the intended ad account
- each integration's `dataset_id` field points to the correct dataset (a `null` value means events are ingested but not routed — see isolation table)
- Pixel domain and CAPI connection ID match the intended environment/business
- the token ID exists on the same CAPI connection; never display token values
- dataset flags such as `is_receiving_events` and `is_receiving_lead_events` fit the symptom

### 2. Inspect event receipt

```bash
api GET "businesses/<business_id>/datasets/<dataset_id>/diagnostics?granularities=HOURLY"
api GET "businesses/<business_id>/datasets/<dataset_id>/diagnostics?granularities=DAILY"
api GET "businesses/<business_id>/datasets/<dataset_id>/diagnostics?granularities=HOURLY&datasource_ids=<datasource_id>"
```

Compare each datasource's event names, counts, timestamps, and `last_activity_ms`. Convert timestamps explicitly and state the timezone. Use hourly data for recent incidents and daily data for trend comparison.

Receipt diagnostics answer “did Spotify receive events?” They do not prove trigger correctness, identifiers, deduplication, campaign data-source selection, or attribution.

### 3. Isolate the layer

| Observation | Likely layer | Next check |
|---|---|---|
| No source receives events | implementation/network | base code or server request, auth, CSP, container, endpoint |
| Pixel absent, CAPI present | browser | base code, trigger, duplicate install, CSP, redirects |
| CAPI absent, Pixel present | server | token/connection pair, payload, 4xx/5xx logs, server GTM container |
| Both present, total inflated | deduplication | same real event uses same `event_id` on both sources |
| Diagnostics present, campaign metrics absent | selection/attribution | dataset shared and selected; date/window/privacy/report fields |
| Wrong site/account receives data | topology/config | domain, business, dataset membership, connection ID |
| Events stopped suddenly | deployment/credential | release time, GTM publish, token revocation, CSP/infrastructure change |
| Integration in dataset but `dataset_id` null | dataset routing | integration was moved via `POST datasets` with multiple `integration_ids`; events are ingested but not routed — fix by removing the integration and re-adding it to a properly-linked dataset |

### 4. Inspect implementation evidence

If the user supplies a public page, browser access, GTM export, or sanitized CAPI example, inspect it read-only:

- Pixel: compare pixel key and base/event code with Ads Manager; search direct installs for `spdt`; inspect console/network/CSP; verify event fires only at the intended action.
- Do not conclude Pixel is absent merely because source HTML lacks `spdt`; tag managers can inject it at runtime.
- Confirm the site is not using both direct and GTM installs.
- Verify redirects preserve Spotify's `spclid` query parameter.
- Web GTM is for Pixel; CAPI GTM requires a server container.
- CAPI: validate envelope, event enum, unique stable event ID, ISO 8601 time, at least one identifier, SHA-256 normalization, optional source URL/action source, and revenue fields.

Never expose secrets or personal data in findings.

## Mutating tests and fixes

Default to a remediation plan. Ask for explicit confirmation immediately before:

- submitting any CAPI event, including a test event
- creating/revoking a token
- changing Pixel/CAPI/dataset metadata
- sharing/unsharing a dataset
- moving an integration between datasets

A test event changes measurement data. Prefer replaying a legitimate known event in a non-production integration with a stable unique `event_id`, and label/document it. Never blindly replay a production POST after a timeout or 5xx.

For source-code or GTM changes, provide the smallest isolated change and an acceptance test; do not claim the Ads API can deploy website or GTM code.

## Attribution boundary

If receipt is healthy but reporting is not:

1. verify the dataset is shared to and selected by the relevant campaign/ad set
2. verify the report date range, entity, and conversion field
3. distinguish total received event activity from attributed conversions
4. account for attribution windows and privacy thresholding
5. route reporting extraction to the `report` skill

Do not “fix” healthy ingestion to force attributed numbers to match internal analytics.

## Incident report

Return:

- symptom and affected scope
- topology diagram in one line: business → dataset → source(s) → ad account
- evidence table with check, result, timestamp/timezone, and confidence
- most likely failing layer and alternatives
- exact remediation by owner
- safe verification steps and wait period
- redacted trace IDs/errors for escalation

Label facts, inferences, and unverified assumptions separately. If the issue remains unresolved, recommend Spotify Ads API support with client ID, endpoint, sanitized request/response, timestamp, and `sp_trace_id`.

## Guardrails

- Begin read-only.
- Wait at least 20 minutes after new event activity before diagnosing empty Ads Manager diagnostics.
- Never request, echo, or store CAPI secrets or personal identifiers.
- Never automatically retry POST, PATCH, or DELETE.
- On 4xx, preserve the sanitized error and stop; on ambiguous POST failure, check receipt/resource state before any retry.
