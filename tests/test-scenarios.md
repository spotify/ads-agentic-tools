# Test Scenarios

10 structured test scenarios for validating the Spotify Ads API plugin. Each scenario covers specific API quirks and plugin behaviors.

**Important:** All entity names (campaigns, ad sets, ads) must be prefixed with `[Test reject]` so they are automatically rejected by ad review and never serve live impressions.

---

**Variables used in curl examples below:**
- `$TOKEN` — OAuth access token from settings
- `$BASE_URL` — `https://api-partner.spotify.com/ads/v3`
- `$SDK_HEADER` — `X-Spotify-Ads-Sdk: claude-code-plugin/$PLUGIN_VERSION` (version from `.claude-plugin/plugin.json`)

---

## Scenario 1: Configure OAuth

**Prompt:** `/spotify-ads-api:configure`

**Quirks tested:** OAuth flow, settings file creation, token validation

**Expected behavior:**
1. Plugin prompts for `client_id` and `client_secret`
2. Runs `oauth-flow.py` to open browser and complete authorization
3. Parses JSON output with `access_token`, `refresh_token`, `expires_in`
4. Prompts for `ad_account_id`, `auto_execute`
5. Writes `.claude/spotify-ads-api.local.md` with all fields
6. Verifies token with test API call

**Success criteria:**
- Settings file exists with all YAML fields populated
- `token_expires_at` is a valid ISO 8601 timestamp in the future
- Test API call returns 200
- Access token and client_secret are masked in output (last 8 chars only)

---

## Scenario 2: List Campaigns

**Prompt:** "Show me all my campaigns"

**Quirks tested:** GET with pagination, auto_execute behavior

**Expected behavior:**
1. Agent reads settings file
2. Constructs: `curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" -H "$SDK_HEADER" "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns?limit=50&sort_direction=DESC"`
3. If `auto_execute` is false, shows command and asks for confirmation
4. Formats response as table: ID | Name | Status | Objective | Created

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/campaigns?limit=50&sort_direction=DESC"
```

**Success criteria:**
- Returns 200 with campaigns list or empty array
- Output formatted as readable table
- Token is masked in displayed command

---

## Scenario 3: Create Campaign

**Prompt:** "Create a campaign called [Test reject] Q1 Brand Awareness with a reach objective"

**Quirks tested:** POST body construction, objective enum, `[Test reject]` prefix for automatic ad review rejection

**Expected behavior:**
1. Agent extracts: name="[Test reject] Q1 Brand Awareness", objective="REACH"
2. Constructs POST request with JSON body
3. Shows curl command for confirmation

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"name":"[Test reject] Q1 Brand Awareness","objective":"REACH"}' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/campaigns"
```

**Success criteria:**
- Request body contains exactly `name` and `objective`
- `name` starts with `[Test reject]`
- Objective is uppercase enum value `REACH`
- Returns 201 with campaign object including `id`

---

## Scenario 4: Create Ad Set with Targeting

**Prompt:** "Create an ad set for that campaign targeting 18-34 year olds in the US on mobile and desktop with a $75/day budget and $20 bid cap"

**Quirks tested:**
- Micro-amounts: $75 -> 75000000, $20 -> 20000000
- `geo_targets` as flat object (NOT array)
- `platforms`: ANDROID, DESKTOP, IOS (NOT "MOBILE")
- `bid_strategy` as plain string (NOT object)
- `category` requirement
- `placements` requirement

**Expected behavior:**
1. Agent converts "$75" to `75000000` micro-amount
2. Agent converts "$20 bid cap" to `bid_micro_amount: 20000000`
3. Maps "mobile and desktop" to `["ANDROID", "IOS", "DESKTOP"]`
4. Sets `geo_targets` as `{"country_code": "US"}` (flat object)
5. Sets `bid_strategy` as string `"MAX_BID"` (not an object)
6. Prompts for `category` (valid ADV_X_Y code)
7. Includes `placements: ["MUSIC"]`

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "[Test reject] ...",
    "campaign_id": "<campaign_id>",
    "start_time": "2026-03-01T00:00:00Z",
    "budget": {"micro_amount": 75000000, "type": "DAILY"},
    "asset_format": "AUDIO",
    "category": "ADV_X_Y",
    "targets": {
      "age_ranges": [{"min": 18, "max": 34}],
      "geo_targets": {"country_code": "US"},
      "platforms": ["ANDROID", "DESKTOP", "IOS"],
      "placements": ["MUSIC"]
    },
    "bid_strategy": "MAX_BID",
    "bid_micro_amount": 20000000
  }' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/ad_sets"
```

**Success criteria:**
- `geo_targets` is `{"country_code": "US"}`, NOT `[{"country_code": "US"}]`
- `platforms` contains `ANDROID`/`IOS`/`DESKTOP`, NOT `MOBILE`
- `bid_strategy` is string `"MAX_BID"`, NOT `{"type": "MAX_BID"}`
- Budget is `75000000`, not `75`
- `bid_micro_amount` is `20000000`, not `20`
- `category` is present and matches `ADV_*` pattern
- `placements` array is present

---

## Scenario 5: Create Audio Ad

**Prompt:** "Create an audio ad for that ad set with a Shop Now button linking to example.com"

**Quirks tested:**
- `call_to_action` uses `key` (not `type`) and `clickthrough_url` (not `url`)
- `companion_asset_id` required for AUDIO format
- Asset selection flow

**Expected behavior:**
1. Agent fetches available assets from `GET /assets`
2. Prompts user to select `asset_id` (audio), `logo_asset_id` (image), `companion_asset_id` (image)
3. Sets `call_to_action.key` to `"SHOP_NOW"` (not `type`)
4. Sets `call_to_action.clickthrough_url` to the URL (not `url`)

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "[Test reject] ...",
    "ad_set_id": "<ad_set_id>",
    "tagline": "...",
    "advertiser_name": "...",
    "assets": {
      "asset_id": "<uuid>",
      "logo_asset_id": "<uuid>",
      "companion_asset_id": "<uuid>"
    },
    "call_to_action": {
      "key": "SHOP_NOW",
      "clickthrough_url": "https://example.com"
    },
    "delivery": "ON"
  }' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/ads"
```

**Success criteria:**
- `call_to_action` has `key` field, NOT `type`
- `call_to_action` has `clickthrough_url` field, NOT `url`
- `companion_asset_id` is present in `assets`
- All three asset IDs are populated

---

## Scenario 6: Full Build-Campaign Flow

**Prompt:** "Build me a complete audio campaign called [Test reject] Summer Promo targeting US listeners aged 25-44 with $100/day budget"

**Quirks tested:** End-to-end multi-step (campaign -> ad set -> ad), ID passing, all quirks combined

**Expected behavior:**
1. Agent presents full plan as tree visualization
2. Creates campaign via POST (extracts `id`)
3. Creates ad set via POST using campaign `id` (extracts ad set `id`)
4. Prompts for assets, creates ad via POST using ad set `id`
5. Displays summary table

**Success criteria:**
- Campaign created with objective (default REACH) and `[Test reject]` prefix in name
- Ad set created with all required fields (budget 100000000, geo_targets flat, platforms correct, category present, placements present, bid_strategy as string) and `[Test reject]` prefix in name
- Ad created with all required assets (including companion_asset_id for AUDIO) and `[Test reject]` prefix in name
- IDs correctly passed from each step to the next
- Final summary shows all created entities

---

## Scenario 7: Pull Aggregate Report

**Prompt:** "Show me impressions, spend, and clicks for all campaigns last month"

**Quirks tested:**
- `fields` as repeated params (`&fields=X&fields=Y`), NOT comma-separated
- Field name is `fields`, NOT `report_fields`
- Date range calculation
- SPEND micro-amount display

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/aggregate_reports?\
entity_type=CAMPAIGN&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&\
granularity=LIFETIME&\
report_start=2026-02-01T00:00:00Z&\
report_end=2026-02-28T23:59:59Z&\
limit=50"
```

**Success criteria:**
- Query parameter is `fields`, NOT `report_fields`
- Fields use repeated parameter format: `fields=IMPRESSIONS&fields=SPEND&fields=CLICKS`
- NOT comma-separated: `fields=IMPRESSIONS,SPEND,CLICKS` (WRONG)
- Date range covers "last month" (February 2026)
- SPEND values converted from micro-amounts for display

---

## Scenario 8: Pause a Campaign

**Prompt:** "Pause the [Test reject] Q1 Brand Awareness campaign"

**Quirks tested:** No DELETE pattern (status change), PATCH not DELETE

**Expected behavior:**
1. Agent searches for campaign by name (GET with filter or list and match)
2. Constructs PATCH request with `{"status": "PAUSED"}`
3. Does NOT attempt DELETE

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"status":"PAUSED"}' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/campaigns/<campaign_id>"
```

**Success criteria:**
- Uses PATCH method, NOT DELETE
- Body contains `{"status": "PAUSED"}`
- Does NOT try to call a DELETE endpoint
- Returns 200 with updated campaign object

---

## Scenario 9: Create Async CSV Report

**Prompt:** "Generate a CSV report of daily impressions and spend by campaign for last month"

**Quirks tested:** Async report creation, different metric names (IMPRESSIONS_ON_SPOTIFY not IMPRESSIONS), status polling

**Expected behavior:**
1. Agent constructs POST body with correct async report fields
2. Uses `IMPRESSIONS_ON_SPOTIFY` (not `IMPRESSIONS` — async reports use different metric names)
3. Sets granularity to `DAY`
4. After creation, shows report ID and suggests polling

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "daily_impressions_spend_feb2026",
    "granularity": "DAY",
    "dimensions": ["CAMPAIGN_NAME"],
    "metrics": ["IMPRESSIONS_ON_SPOTIFY", "SPEND"],
    "report_start": "2026-02-01T00:00:00Z",
    "report_end": "2026-02-28T23:59:59Z"
  }' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/async_reports"
```

**Success criteria:**
- Uses `IMPRESSIONS_ON_SPOTIFY`, NOT `IMPRESSIONS`
- `granularity` is `DAY`
- Date range is correct for "last month"
- Response includes report `id` for status polling
- Agent suggests checking status with async-status command

---

## Scenario 10: Token Refresh

**Prompt:** Run any API command with an expired token (set `token_expires_at` to a past date in settings)

**Quirks tested:** Auto-refresh hook, token update, retry with new token

**Setup:**
Edit `.claude/spotify-ads-api.local.md` and set `token_expires_at` to `2026-02-01T00:00:00Z` (in the past). Ensure `refresh_token`, `client_id`, and `client_secret` are populated.

**Expected behavior:**
1. User runs a command (e.g., "Show me all campaigns")
2. PreToolUse hook detects the curl targets `api-partner.spotify.com`
3. Hook reads settings, sees `token_expires_at` is in the past
4. Hook runs `refresh-token.py` with stored credentials
5. Hook updates settings file with new `access_token` and `token_expires_at`
6. Original API call proceeds with the new token
7. API call succeeds

**Success criteria:**
- Token refresh happens automatically without user intervention
- Settings file updated with new `access_token` and future `token_expires_at`
- API call succeeds with the refreshed token
- No manual re-authentication required

---

## Scenario 11: Upload Asset

**Prompt:** `/spotify-ads-api:assets upload /path/to/my-creative.mp3`

**Quirks tested:** Two-step create-then-upload flow, multipart form-data, status polling, file type detection

**Expected behavior:**
1. Plugin detects `.mp3` extension → asset type `AUDIO`
2. Prompts for asset name (defaults to `my-creative`)
3. Creates asset metadata via `POST /assets` with `{"asset_type":"AUDIO","name":"my-creative"}`
4. Extracts `id` from response
5. Checks file size — if ≤ 20MB, uploads via `POST /assets/{id}/upload` with multipart form-data
6. Polls `GET /assets/{id}` every 3 seconds until status is `READY` or `REJECTED`
7. Displays asset ID, name, type, status, and URL

**Expected curl (create):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"asset_type":"AUDIO","name":"my-creative"}' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/assets"
```

**Expected curl (upload):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -F "media=@/path/to/my-creative.mp3" \
  -F "asset_type=AUDIO" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/assets/<asset_id>/upload"
```

**Success criteria:**
- Asset type correctly detected from file extension
- Two-step flow: metadata creation, then file upload
- Upload uses multipart form-data (`-F` flags), not JSON
- Status polling runs until asset reaches `READY` or `REJECTED`
- Final display shows asset ID usable in ad creation

---

## Scenario 12: Pre-flight Audience Estimate

**Prompt:** "Build me a video campaign called [Test reject] Narrow Test targeting US listeners aged 50-54 in Portland with $25/day budget"

**Quirks tested:** Pre-flight audience validation, `POST /estimates/audience` (top-level, not under ad_accounts), narrow targeting warning

**Expected behavior:**
1. Plugin parses the campaign plan (VIDEO, ages 50-54, geo: Portland/US)
2. After user confirms the plan, runs `POST /estimates/audience` for the ad set targeting
3. Endpoint is top-level: `https://api-partner.spotify.com/ads/v3/estimates/audience` (NOT under `/ad_accounts/{id}/`)
4. Displays audience estimate (projected users, reach, impressions, CPM)
5. If audience is too small (likely with VIDEO + narrow age + single city), warns user
6. Suggests: broaden age range, add platforms, switch to AUDIO, expand geo
7. Asks whether to proceed, adjust, or cancel

**Expected curl (estimate):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "ad_account_id": "<account_id>",
    "start_date": "2026-03-01T00:00:00Z",
    "asset_format": "VIDEO",
    "objective": "REACH",
    "bid_strategy": "MAX_BID",
    "bid_micro_amount": 15000000,
    "budget": {"micro_amount": 25000000, "type": "DAILY", "currency": "USD"},
    "targets": {
      "age_ranges": [{"min": 50, "max": 54}],
      "geo_targets": {"country_code": "US"},
      "platforms": ["ANDROID", "DESKTOP", "IOS"],
      "placements": ["MUSIC"]
    }
  }' \
  "https://api-partner.spotify.com/ads/v3/estimates/audience"
```

**Success criteria:**
- Audience estimate runs BEFORE ad set creation (not after)
- Endpoint is top-level `/estimates/audience`, NOT under `/ad_accounts/{id}/`
- Warning displayed when audience is too small
- User given options to proceed, adjust, or cancel
- If user adjusts targeting, estimate re-runs with new parameters

---

## Scenario 13: Dashboard

**Prompt:** `/spotify-ads-api:dashboard`

**Quirks tested:** Micro-amount to dollar conversion for spend, aggregate report field format, active campaign filtering, zero-impression filtering

**Expected behavior:**
1. Plugin fetches aggregate report for active campaigns (entity_type=CAMPAIGN, statuses=ACTIVE)
2. Uses repeated `fields` parameters (`&fields=IMPRESSIONS&fields=SPEND&...`), NOT comma-separated
3. Fetches campaign details for names and budget info
4. Displays formatted table with campaign metrics
5. Spend values converted from micro-amounts to dollars (e.g., 450000000 → $450.00)
6. Rows with zero impressions are filtered out
7. Shows pacing info when budget data is available

**Expected curl (metrics):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/aggregate_reports?\
entity_type=CAMPAIGN&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&fields=FREQUENCY&fields=CTR&fields=COMPLETES&\
granularity=LIFETIME&\
entity_status_type=CAMPAIGN&\
statuses=ACTIVE&\
limit=50"
```

**Success criteria:**
- Spend displayed in dollars (`$450.00`), NOT micro-amounts (`450000000`)
- Fields use repeated parameter format, NOT comma-separated
- All active campaigns appear in the table
- Zero-impression rows are excluded
- Table is cleanly formatted with aligned columns
- Total spend is shown in the header summary
