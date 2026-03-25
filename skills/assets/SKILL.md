---
name: assets
description: Upload, list, and manage Spotify Ads API creative assets — audio, video, and images for ad campaigns.
argument-hint: "upload <file_path> | list [audio|video|image] | get <asset_id> | archive <asset_id>"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Asset Management

Upload, list, retrieve, and archive creative assets (audio, video, images) for use in ads.

## Setup

1. Read `.claude/spotify-ads-api.local.md` for `access_token`, `ad_account_id`, `environment`, `auto_execute`.
2. Base URL:
   - sandbox: `https://api-partner.spotify.com/ads-sandbox/v3`
   - production: `https://api-partner.spotify.com/ads/v3`
3. If settings file is missing, instruct the user to run `/spotify-ads-api:configure` first.
4. Read `.claude-plugin/plugin.json` to get the plugin `version`. Include `-H "X-Spotify-Ads-Sdk: claude-code-plugin/$PLUGIN_VERSION"` on all API requests.

## Parsing Arguments

The argument format is: `<operation> [arg]`
- `upload <file_path>` — Upload a new asset
- `list [audio|video|image]` — List assets, optionally filtered by type
- `get <asset_id>` — Get details of a specific asset
- `archive <asset_id>` — Archive an asset
- `unarchive <asset_id>` — Unarchive an asset
- If no argument, ask which operation.

---

## Operations

### `upload <file_path>`

Two-step process following the API's required flow.

#### Step 1: Detect asset type from file extension

| Extensions | Asset Type |
|------------|------------|
| `.mp3`, `.wav`, `.ogg` | AUDIO |
| `.mp4`, `.mov` | VIDEO |
| `.png`, `.jpg`, `.jpeg` | IMAGE |

If the extension doesn't match any of these, ask the user to specify the asset type.

#### Step 2: Prompt for name

Use AskUserQuestion to ask for the asset name (2-120 characters). Default to the filename without extension.

#### Step 3: Create asset metadata

```bash
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "X-Spotify-Ads-Sdk: claude-code-plugin/$PLUGIN_VERSION" \
  -H "Content-Type: application/json" \
  -d '{"asset_type":"AUDIO","name":"my-creative"}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/assets"
```

Extract `id` from the response.

#### Step 4: Upload the file

First, check the file size:

```bash
stat -f%z "/path/to/file"  # macOS
# or: stat --printf="%s" "/path/to/file"  # Linux
```

**If file is <= 20MB** — Simple upload:

```bash
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -F "media=@/path/to/file" \
  -F "asset_type=AUDIO" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/assets/$ASSET_ID/upload"
```

**If file is > 20MB** — Chunked upload:

1. Start the chunked upload session:
```bash
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/assets/$ASSET_ID/chunked_upload/start"
```
Extract `upload_session_id` and `max_chunk_size_mb` from the response.

2. Split the file into chunks:
```bash
split -b ${MAX_CHUNK_SIZE_MB}m /path/to/file /tmp/chunk_
```

3. Upload each chunk (numbered starting from 1):
```bash
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -F "media=@/tmp/chunk_aa" \
  -F "upload_section=1" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/assets/$ASSET_ID/chunked_upload/transfer"
```

4. Complete the chunked upload:
```bash
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"upload_session_id":"<session_id>","number_of_sections":<total_chunks>}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/assets/$ASSET_ID/chunked_upload/complete"
```

5. Clean up temp chunks:
```bash
rm /tmp/chunk_*
```

#### Step 5: Poll for processing status

After upload, poll `GET /assets/{id}` until status changes from `PROCESSING` to `READY` or `REJECTED`. Poll every 3 seconds, max 60 seconds.

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/assets/$ASSET_ID"
```

Check the `status` field in the response. If still `PROCESSING`, wait 3 seconds and retry.

#### Step 6: Display result

Show the final asset details:
- **Asset ID** — the UUID
- **Name** — the asset name
- **Type** — AUDIO, VIDEO, or IMAGE
- **Status** — READY, PROCESSING, or REJECTED
- **URL** — if available (when status is READY)
- **Duration** — for audio/video assets
- **Dimensions** — for image/video assets
- **Aspect ratio** — for video/image assets

If the asset was REJECTED, explain that the file may not meet format requirements and suggest checking the supported formats section below.

---

### `list [audio|video|image]`

List assets in the account, optionally filtered by type.

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/assets?asset_types=AUDIO&limit=50&sort_direction=DESC"
```

If no type filter is provided, omit the `asset_types` parameter to list all assets.

Format as table:

| ID | Name | Type | Status | Duration/Dimensions | Created |
|----|------|------|--------|---------------------|---------|

- For audio assets: show duration
- For video assets: show duration and dimensions
- For image assets: show dimensions
- Filter out archived assets unless the user specifically asks for them

If `continuation_token` is present in the response, note that more assets exist.

---

### `get <asset_id>`

Get full details of a specific asset.

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/assets/$ASSET_ID"
```

Display all fields in readable format:
- For **audio**: show name, type, status, duration, URL
- For **video**: show name, type, status, duration, aspect ratio, dimensions, has_audio, URL
- For **image**: show name, type, status, dimensions, aspect ratio, URL

---

### `archive <asset_id>` / `unarchive <asset_id>`

Archive or unarchive an asset using the bulk action endpoint.

```bash
curl -s -X PATCH -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"action":"ARCHIVE","ids":["<asset_id>"]}' \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/assets"
```

For unarchive, use `"action":"UNARCHIVE"`.

Confirm the action completed by displaying the updated asset status.

---

## Supported Formats

| Type | Formats | Recommendations |
|------|---------|-----------------|
| Audio | MP3, WAV, OGG | 128kbps+, 44.1kHz+ sample rate |
| Video | MP4, MOV | Aspect ratios: 16:9, 1.91:1, 1:1, 9:16 |
| Image | PNG, JPEG | — |

- **Max file size (simple upload):** 20MB
- **Asset naming:** 2-120 characters

## Execution Behavior

- If `auto_execute` is `true`, execute each API call directly.
- If `auto_execute` is `false`, present the curl command and ask for confirmation before executing.
- Display responses in readable format.
- On error, show the error message from the response body.
