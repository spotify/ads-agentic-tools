---
name: measurement-setup
description: "Plan and configure Spotify Ads conversion measurement with Spotify Pixel, direct or Google Tag Manager-based Conversions API (CAPI), datasets, advanced matching, mobile apps, event mapping, parameters, ad-account sharing, and CAPI credentials. Use when a user asks to design or implement measurement, install Pixel, integrate CAPI, combine browser and server events, register an app, create a dataset, or prepare a measurement implementation plan. For broken or inconsistent existing implementations, use measurement-debug."
---

# Spotify Ads API — Measurement Setup

Design the event plan first, then configure Spotify resources, then hand off implementation and verification.

## Setup

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" measurement-setup "$@"; }
```

Measurement paths require a `business_id`. Discover it with `GET businesses` when absent; do not confuse it with `ad_account_id`.

Read [implementation-guide.md](references/implementation-guide.md) before recommending Pixel, CAPI, datasets, advanced matching, event names, parameters, identifiers, or GTM.

## Intake and recommendation

Ask only for details that affect the design:

- website, app, offline, or mixed conversion sources
- direct code, web GTM, server GTM, or another implementation owner
- business ID and ad account(s) that need access
- business outcomes and the site/app actions that represent them
- whether the same event will be sent by both Pixel and CAPI
- available identifiers, consent constraints, and secret-management owner
- transaction fields available for revenue measurement

Recommend:

- **Pixel** for browser-side website events and automatic page views.
- **CAPI** for server-side web, app, or offline events and stronger control over event payloads.
- **Pixel + CAPI in one dataset** for complementary browser/server coverage. Use the same stable `event_id` for the same real-world event so Spotify can deduplicate it.
- **Mobile app registration** when app attribution is supplied by a supported mobile measurement partner.

Produce an implementation matrix before creating resources:

| Business action | Spotify event | Source(s) | Trigger | Event ID | Identifiers | Parameters | Consent/owner |
|---|---|---|---|---|---|---|---|

Do not invent mappings. Document what each custom slot means because `CUSTOM_EVENT_1` through `CUSTOM_EVENT_5` cannot be renamed.

## Resource workflow

1. Inventory existing Pixels, CAPI integrations, mobile apps, and datasets.
2. Agree on the event matrix and source topology.
3. Reuse compatible resources; create only what is missing.
4. Create integrations in the correct order: Pixel first (auto-creates a dataset), then CAPI with `dataset_id` pointing to the Pixel's dataset. See "Pixel + CAPI in one dataset" under Datasets.
5. Share the dataset or mobile app with the intended ad account.
6. Give the implementation owner source-specific code/payload requirements.
7. After implementation, wait at least 20 minutes before treating missing diagnostics as a failure; then use `measurement-debug`.

Never promise attribution, optimization, or reporting merely because ingestion is configured.

## Pixel resources

```bash
api GET "businesses/<business_id>/pixels?include_events=true"
api POST "businesses/<business_id>/pixels" \
  '{"name":"Web Pixel","domain":"https://example.com","aam_opt_in":true,"aam_fields":["EMAIL","PHONE"]}'
api GET "businesses/<business_id>/pixels/<pixel_id>"
api PATCH "businesses/<business_id>/pixels/<pixel_id>" \
  '{"name":"Updated Pixel","domain":"https://example.com"}'
```

The API creates and configures the Pixel resource; it does not install JavaScript on the user's site. Provide the correct implementation path:

- Direct install: base code sitewide, ideally in the document header, plus event code at the actual action or confirmation.
- Web GTM: Custom HTML tags, with the base code present whenever an event fires.
- Base code records page views. Additional events require their own trigger.
- Do not advise simultaneous direct and tag-manager installation.

The Pixel list endpoint (`GET pixels`) may return 403 for some businesses. If it does, fall back to checking the `pixel` field on individual dataset responses (`GET datasets/<dataset_id>`) to verify Pixel configuration.

Pixel events are read-only. The API does not expose Pixel deletion or arbitrary custom-event creation. Event activity is total received site activity, not attributed campaign results.

For advanced matching, obtain explicit approval and select only fields the site actually collects under its privacy/consent rules. API enum support may be broader than the current Ads Manager UI.
The Ads API create request accepts advanced-matching settings, but the Pixel update endpoint exposes only name and domain; do not promise an API-based AAM change to an existing Pixel.

## CAPI resources and credentials

```bash
api POST "businesses/<business_id>/capi" \
  '{"name":"Web Conversions","dataset_id":"<dataset_id>"}'
api GET "businesses/<business_id>/capi/<capi_connection_id>"
api PATCH "businesses/<business_id>/capi/<capi_connection_id>" \
  '{"name":"Updated Conversions"}'
```

The `dataset_id` field is optional. Omitting it auto-creates a new dataset for the CAPI connection. To add CAPI to an existing dataset (e.g. one that already contains a Pixel), pass that dataset's ID explicitly.

Create, list, or revoke tokens:

```bash
api POST "businesses/<business_id>/capi/<capi_connection_id>/tokens"
api GET "businesses/<business_id>/capi/<capi_connection_id>/tokens"
api DELETE "businesses/<business_id>/capi/<capi_connection_id>/tokens/<token_id>"
```

CAPI event submission uses `POST https://capi.spotify.com/capi-direct/events/`, not the Ads API wrapper. Read the direct-event contract in the implementation guide before producing a payload.

Security and execution rules:

- The CAPI token is long-lived, distinct from Ads API OAuth, and must match its connection ID.
- At most three CAPI tokens may exist for a connection. Revoke an old token before creating another only with explicit confirmation.
- Token create and list responses contain active secret values. Treat the full response as secret, never print or repeat it in chat, logs, or command summaries, and expose only redacted token IDs/counts. Arrange for a newly created token to be captured directly into the user's secret manager; if that is not possible, stop and have the user create and store it through a secure path rather than exposing it in the conversation.
- Never submit a sample/test conversion event without explicit confirmation of the destination and expected effect; it changes measurement data.
- If authorized to submit, redact identifiers and tokens from displayed commands and output.
- Do not automatically retry POST. The implementation owner may retry transient 5xx with bounded backoff and a stable `event_id`; never retry a non-timeout 4xx unchanged.

## Datasets and sharing

```bash
api GET "businesses/<business_id>/datasets"
api POST "businesses/<business_id>/datasets" \
  '{"name":"US Web Conversions","integration_ids":["<integration_id>"]}'
api GET "businesses/<business_id>/datasets/<dataset_id>"
api PATCH "businesses/<business_id>/datasets/<dataset_id>" \
  '{"name":"Updated Dataset"}'
api POST "businesses/<business_id>/datasets/<dataset_id>/ad_accounts/<ad_account_id>"
api DELETE "businesses/<business_id>/datasets/<dataset_id>/ad_accounts/<ad_account_id>"
```

The `GET datasets` endpoint does not accept `limit` or `offset` parameters.

A dataset combines Pixel and CAPI sources and enables cross-source deduplication. It is recommended when both sources report the same outcomes, but is not required for a single source.

### Pixel + CAPI in one dataset

When both Pixel and CAPI are needed, create them in this order to ensure proper dataset routing:

1. Create the Pixel first — it auto-creates a dataset with a valid `dataset_id` link.
2. Create the CAPI connection with `dataset_id` set to the Pixel's auto-created dataset ID.
3. Share the dataset with the ad account.

Do **not** create both integrations independently and then use `POST datasets` with both `integration_ids` to combine them. This can leave the Pixel's internal `dataset_id` as `null`, causing the ingestion pipeline to receive Pixel events but fail to route them to the dataset for diagnostics or attribution.

If integrations were already created independently and need to stay in separate datasets, that is acceptable — deduplication is only needed when the same real-world event is sent by both sources.

### Removing an integration

Removing an integration moves it into a new auto-created dataset:

```bash
api DELETE "businesses/<business_id>/datasets/<dataset_id>/integrations/<integration_id>"
```

Explain that side effect and require explicit confirmation. Require confirmation before unsharing too.

## Mobile apps

```bash
api GET "businesses/<business_id>/mobile_apps"
api POST "businesses/<business_id>/mobile_apps" \
  '{"mobile_app":{"name":"My App","platform":"IOS","platform_app_id":"<app_id>","ad_type":"VIEW_THROUGH","mobile_measurement_partner":"APPS_FLYER"}}'
api GET "businesses/<business_id>/mobile_apps/<mobile_app_id>"
api PATCH "businesses/<business_id>/mobile_apps/<mobile_app_id>" \
  '{"name":"My App","platform":"IOS","platform_app_id":"<app_id>"}'
api POST "businesses/<business_id>/mobile_apps/<mobile_app_id>/ad_accounts/<ad_account_id>"
api DELETE "businesses/<business_id>/mobile_apps/<mobile_app_id>/ad_accounts/<ad_account_id>"
```

Schema-supported partners are `KOCHAVA`, `APPS_FLYER`, `ADJUST`, and `BRANCH`. Do not imply that registration installs or configures the partner SDK.

## Completion report

Return:

- resource topology: business → dataset → Pixel/CAPI → shared ad accounts
- event matrix and deduplication key design
- identifiers, hashing, parameters, consent, and secret ownership
- implementation tasks by owner
- verification plan and the 20-minute diagnostic delay
- unresolved assumptions and risks

## Guardrails

- Confirm business, resource, and ad-account IDs before mutation.
- Present the exact plan before sharing/unsharing, token creation/revocation, or integration moves.
- Do not claim support for Direct IO, SAX, PG, or another buying channel merely because an API resource exists.
- Do not claim tCPA/tROAS optimization or guaranteed cross-device attribution.
- Use `measurement-debug` for an existing broken setup.
- Check `HTTP_STATUS:` first. On 4xx, show the sanitized error and stop.
