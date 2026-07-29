---
name: audiences
description: "Manage Spotify Ads API audiences: upload or replace customer lists, create custom web-event or ad-engagement audiences, create lookalikes, list/get/edit audiences, inspect eligible datasets, and delete audiences. Use when a user asks to onboard first-party data, retarget people who saw or clicked ads, build an event-based audience, create a lookalike, replace an audience file, check audience status, or remove an audience."
---

# Spotify Ads API — Audience Management

Manage audiences scoped to the configured ad account.

## Setup

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" audiences "$@"; }
```

Run `api --env` when raw upload curl needs the configured environment.

## Operations

### List or get

```bash
api GET "ad_accounts/{ad_account_id}/audiences?limit=50&offset=0"
api GET "ad_accounts/{ad_account_id}/audiences/<audience_id>"
api GET "ad_accounts/{ad_account_id}/audiences/datasets?limit=50"
```

Paginate list results. Filter with repeated `audience_types`, `audience_ids`, or `q` only when requested. Show audience type, subtype, source, status, size range, and ID.

### Upload a customer list

1. Validate that the local file exists and identify its exact path. Never print its contents.
2. Request a signed upload URL:

```bash
api POST "ad_accounts/{ad_account_id}/audiences/upload_url"
```

3. Capture both returned `id` and `upload_url`.
4. Upload the file directly to the signed URL with raw curl. Do not add Ads API authorization or tracking headers to the signed URL:

```bash
curl -sS -X PUT --upload-file "<file_path>" "<upload_url>"
```

5. Create the audience using the returned ID:

```json
{
  "audience_type": "CUSTOM",
  "name": "Q4 CRM",
  "description": "Customer list for Q4",
  "audience_id": "<upload_id>",
  "subtype": "CUSTOMER_LIST"
}
```

Do not automatically retry the upload or create request. If either result is ambiguous, get the audience by the returned ID before proposing another attempt.

### Replace a customer-list file

Request `POST ad_accounts/{ad_account_id}/audiences/upload_url/{audience_id}`, then upload to the returned signed URL. Replacing audience data is destructive: show the audience ID, name, and file path and require explicit confirmation immediately before requesting the replacement URL.

### Create event or engagement audiences

Web-event audience:

```json
{
  "audience_type": "CUSTOM",
  "name": "Cart Abandoners",
  "subtype": "WEB_EVENT",
  "dataset_ids": ["<dataset_id>"],
  "included_events": ["ADDTOCART"],
  "excluded_events": ["PURCHASE"],
  "lookback_days": 30
}
```

Ad-engagement audience:

```json
{
  "audience_type": "CUSTOM",
  "name": "Campaign Clickers",
  "subtype": "AD_ENGAGEMENT",
  "campaign_ids": ["<campaign_id>"],
  "exposure_type": "CLICKS",
  "lookback_days": 30
}
```

Use `ad_set_ids` instead of `campaign_ids` when the user scopes the audience to ad sets. `exposure_type` is `IMPRESSIONS` or `CLICKS`. `lookback_days` is 30, 60, 90, or 180.

### Create a lookalike

```json
{
  "audience_type": "LOOKALIKE",
  "name": "Q4 CRM Lookalike",
  "seed_audience_id": "<seed_audience_id>"
}
```

Fetch the seed first and confirm it is the intended audience. Do not claim control over lookalike percentage or expansion because the public request schema exposes no such field.

### Edit or delete

PATCH edits only name and description and must include `audience_type`.

```bash
api PATCH "ad_accounts/{ad_account_id}/audiences/<audience_id>" \
  '{"audience_type":"CUSTOM","name":"Updated name"}'
```

DELETE permanently removes an audience. Fetch it first, state its name, type, status, and ID, and require explicit confirmation immediately before DELETE, even when `auto_execute` is true.

## Guardrails

- Never display, log, summarize, or persist customer-list contents.
- Do not claim audience-overlap estimates; no overlap endpoint exists.
- Do not claim arbitrary bulk upload. Process files one at a time and confirm the intended mapping of file to audience name.
- Status is asynchronous (`PROCESSING`, `LEARNING`, `BOOKABLE`, `LIVE`, and others). Report the current status without promising completion time.
- Only retry GET on network errors or 5xx. Never automatically retry POST, PATCH, PUT, or DELETE.
- Check `HTTP_STATUS:` before parsing. On a non-timeout 4xx, show the API error and do not retry.
