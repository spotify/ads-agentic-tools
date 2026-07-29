---
name: measurement-setup
description: "Configure and diagnose Spotify Ads API measurement resources: mobile apps, Spotify Pixel, Conversion API integrations and auth tokens, measurement datasets, ad-account sharing, and event diagnostics. Use when a user asks to set up Pixel or CAPI, register an iOS/Android app, connect supported mobile measurement metadata, create or organize datasets, share measurement resources with an ad account, rotate CAPI tokens, or investigate whether conversion events are arriving."
---

# Spotify Ads API — Measurement Setup

Manage business-scoped measurement resources and their ad-account sharing.

## Setup

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" measurement-setup "$@"; }
```

Measurement paths require a `business_id`. Discover it with `GET businesses` when absent; do not confuse it with `ad_account_id`.

## Resource workflow

Use this order for a complete setup:

1. Inspect existing Pixels, CAPI integrations, mobile apps, and datasets.
2. Create or update the requested integration.
3. Create or select a dataset that groups integration IDs.
4. Share the dataset or mobile app with the intended ad account.
5. Read diagnostics to verify event receipt.

Never promise attribution, optimization, or reporting fields merely because event ingestion is configured.

## Pixel

```bash
api GET "businesses/<business_id>/pixels?include_events=true&limit=50&offset=0"
api POST "businesses/<business_id>/pixels" \
  '{"name":"Web Pixel","domain":"https://example.com","aam_opt_in":true,"aam_fields":["EMAIL","PHONE"]}'
api GET "businesses/<business_id>/pixels/<pixel_id>"
api PATCH "businesses/<business_id>/pixels/<pixel_id>" \
  '{"name":"Updated Pixel","domain":"https://example.com"}'
```

Pixel events are read-only. Supported standard events include `PAGE_VIEW`, `LEAD`, `PURCHASE`, and `ADD_TO_CART`; received signal metadata may include five custom event slots. The API does not expose Pixel delete/archive or arbitrary custom-event creation.

## Conversion API

Create an integration:

```bash
api POST "businesses/<business_id>/capi" \
  '{"name":"Web Conversions","dataset_id":"<dataset_id>"}'
```

Get or rename:

```bash
api GET "businesses/<business_id>/capi/<capi_connection_id>"
api PATCH "businesses/<business_id>/capi/<capi_connection_id>" \
  '{"name":"Updated Conversions"}'
```

Create, list, or revoke tokens:

```bash
api POST "businesses/<business_id>/capi/<capi_connection_id>/tokens"
api GET "businesses/<business_id>/capi/<capi_connection_id>/tokens"
api DELETE "businesses/<business_id>/capi/<capi_connection_id>/tokens/<token_id>"
```

A newly created token is a secret. Show it once, avoid command echo/history where possible, never write it to the plugin settings file, and instruct the user to store it in their secret manager. List operations should show token IDs and creation metadata, not full token values. Require explicit confirmation before revocation.

## Datasets

```bash
api GET "businesses/<business_id>/datasets?limit=50&offset=0"
api POST "businesses/<business_id>/datasets" \
  '{"name":"US Web Conversions","integration_ids":["<integration_id>"]}'
api GET "businesses/<business_id>/datasets/<dataset_id>"
api PATCH "businesses/<business_id>/datasets/<dataset_id>" \
  '{"name":"Updated Dataset"}'
```

Share or unshare:

```bash
api POST "businesses/<business_id>/datasets/<dataset_id>/ad_accounts/<ad_account_id>"
api DELETE "businesses/<business_id>/datasets/<dataset_id>/ad_accounts/<ad_account_id>"
```

Get event diagnostics:

```bash
api GET "businesses/<business_id>/datasets/<dataset_id>/diagnostics?granularities=DAILY"
```

Report event counts and last activity by datasource. Diagnostics verify receipt, not correctness of attribution.

Removing an integration from a dataset moves it into a new dataset:

```bash
api DELETE "businesses/<business_id>/datasets/<dataset_id>/integrations/<integration_id>"
```

Explain that side effect and require explicit confirmation.

## Mobile apps

```bash
api GET "businesses/<business_id>/mobile_apps"
api POST "businesses/<business_id>/mobile_apps" \
  '{"mobile_app":{"name":"My App","platform":"IOS","platform_app_id":"<app_id>","ad_type":"VIEW_THROUGH","mobile_measurement_partner":"APPS_FLYER"}}'
api GET "businesses/<business_id>/mobile_apps/<mobile_app_id>"
api PATCH "businesses/<business_id>/mobile_apps/<mobile_app_id>" \
  '{"name":"My App","platform":"IOS","platform_app_id":"<app_id>"}'
```

Supported measurement partners in the schema are `KOCHAVA`, `APPS_FLYER`, `ADJUST`, and `BRANCH`.

Share or unshare:

```bash
api POST "businesses/<business_id>/mobile_apps/<mobile_app_id>/ad_accounts/<ad_account_id>"
api DELETE "businesses/<business_id>/mobile_apps/<mobile_app_id>/ad_accounts/<ad_account_id>"
```

Require explicit confirmation before unsharing.

## Guardrails

- Confirm business, resource, and ad-account IDs before any mutation.
- Treat share/unshare, token creation/revocation, and integration moves as consequential changes; present the exact plan first.
- Do not claim support for named third-party integrations beyond enum-backed fields.
- Do not claim this skill enables CAPI for Direct IO, SAX, PG, or another buying channel.
- Do not claim tCPA/tROAS optimization, cross-device attribution, cost-data sharing, or browser-side Pixel debugging.
- Only retry GET on network errors or 5xx. Never automatically retry POST, PATCH, or DELETE.
- Check `HTTP_STATUS:` first. On 4xx, show the error and stop.
