# Test Scenarios

21 structured test scenarios for validating the Spotify Ads API plugin. Each scenario covers specific API quirks and plugin behaviors.

**Important:** All entity names (campaigns, ad sets, ads) must be prefixed with `[Test reject]` so they are automatically rejected by ad review and never serve live impressions.

---

**Variables used in curl examples below:**
- `$TOKEN` — OAuth access token from settings
- `$BASE_URL` — `https://api-partner.spotify.com/ads/v3`
- `$SDK_HEADER` — `X-Spotify-Ads-Sdk: $SDK_PRODUCT/$PLUGIN_VERSION`, where `SDK_PRODUCT` is `codex-plugin` on Codex, `claude-code-plugin` on Claude, and `gemini-cli-extension` on Gemini

---

## Scenario 1: Configure OAuth

**Prompt:** `/spotify-ads-api:configure` (`/configure` on Gemini)

**Quirks tested:** OAuth flow, settings file creation, token validation

**Expected behavior:**
1. Plugin prompts for `client_id` and `client_secret`
2. Runs `oauth-flow.py` to open browser and complete authorization
3. Parses JSON output with `access_token`, `refresh_token`, `expires_in`
4. Prompts for `ad_account_id`, `auto_execute`
5. Writes the active platform settings file (`.codex/spotify-ads-api.local.md` on Codex, `.claude/spotify-ads-api.local.md` on Claude, `.gemini/spotify-ads-api.local.md` on Gemini) with all fields
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
    "category": "ADV_1_5",
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

## Scenario 6: Full Build-Campaign Flow (Draft Default)

**Prompt:** "Build me a complete audio campaign called [Test reject] Summer Promo targeting US listeners aged 25-44 with $100/day budget"

**Quirks tested:** End-to-end multi-step draft creation (draft campaign -> draft ad set -> draft ad), ID passing, draft_hierarchy_version, auto-validation, all schema quirks combined

**Expected behavior:**
1. Agent presents full plan as tree visualization, labeled as **DRAFT**
2. Prompts for assets
3. Creates **draft** campaign via `POST /drafts/campaigns` (extracts draft campaign `id`)
4. Creates **draft** ad set via `POST /drafts/ad_sets` using draft campaign `id` (extracts draft ad set `id`)
5. Creates **draft** ad via `POST /drafts/ads` using draft ad set `id`
6. Fetches draft campaign to get current `draft_hierarchy_version`
7. Runs validation with that version
8. Displays validation results and summary table
9. Asks: publish now or keep as draft

**Success criteria:**
- Uses draft endpoints (`/drafts/campaigns`, `/drafts/ad_sets`, `/drafts/ads`), NOT direct entity endpoints
- Tree visualization labels entities as "DRAFT"
- Draft campaign created with objective (default REACH) and `[Test reject]` prefix in name
- Draft ad set created with all required fields (budget 100000000, geo_targets flat, platforms correct, category present, placements present, bid_strategy as string) and `[Test reject]` prefix in name
- Draft ad created with all required assets (including companion_asset_id for AUDIO) and `[Test reject]` prefix in name
- Draft IDs correctly passed from each step to the next
- `draft_hierarchy_version` fetched fresh before validation (not reused from creation response)
- Validation runs automatically after all drafts are created
- If user requests publish, explicit confirmation is required even with `auto_execute: true`

**Note:** If the user explicitly says "skip drafts" or "create live entities", the agent should use direct endpoints instead (legacy behavior).

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
Edit the active platform settings file (`.codex/spotify-ads-api.local.md` on Codex, `.claude/spotify-ads-api.local.md` on Claude, `.gemini/spotify-ads-api.local.md` on Gemini) and set `token_expires_at` to `2026-02-01T00:00:00Z` (in the past). Ensure `refresh_token`, `client_id`, and `client_secret` are populated.

**Expected behavior:**
1. User runs a command (e.g., "Show me all campaigns")
2. The pre-tool hook (`PreToolUse` on Claude/Codex, `BeforeTool` on Gemini) detects the curl targets `api-partner.spotify.com`
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

---

## Scenario 14: List Draft Campaigns

**Prompt:** "Show me all my draft campaigns"

**Quirks tested:** Draft list endpoint (not live campaigns endpoint), table formatting, `draft_hierarchy_version` display

**Expected behavior:**
1. Agent reads settings file
2. Constructs GET to `/drafts/campaigns` (NOT `/campaigns`)
3. Formats response as table: Draft ID | Name | Status | Objective | Version | Created

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/drafts/campaigns?limit=50&sort_direction=DESC"
```

**Success criteria:**
- Uses `/drafts/campaigns` endpoint, NOT `/campaigns`
- Output includes `draft_hierarchy_version` column
- Returns 200 with drafts list or empty array
- Output formatted as readable table

---

## Scenario 15: Create Draft Campaign Hierarchy (Explicit)

**Prompt:** `/spotify-ads-api:drafts build [Test reject] Audio Draft Campaign targeting US listeners aged 25-44 with $50/day budget and a Learn More button linking to example.com`

**Quirks tested:** Draft-specific skill invocation, sequential draft entity creation, `campaign_id` references draft (not live) ID, `ad_set_id` references draft (not live) ID, auto-validation after creation

**Expected behavior:**
1. Agent presents plan as tree with DRAFT labels
2. Prompts for assets (fetches from `GET /assets`)
3. Creates draft campaign: `POST /drafts/campaigns`
4. Creates draft ad set: `POST /drafts/ad_sets` with `campaign_id` = draft campaign ID
5. Creates draft ad: `POST /drafts/ads` with `ad_set_id` = draft ad set ID
6. Fetches draft campaign to get current `draft_hierarchy_version`
7. Validates with that version
8. Displays summary and asks: publish or keep as draft

**Expected curl (draft campaign):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"name":"[Test reject] Audio Draft Campaign","objective":"REACH"}' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/drafts/campaigns"
```

**Expected curl (draft ad set):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "campaign_id": "<draft_campaign_id>",
    "name": "[Test reject] Audio Draft Ad Set",
    "start_time": "2026-07-01T00:00:00Z",
    "budget": {"micro_amount": 50000000, "type": "DAILY"},
    "asset_format": "AUDIO",
    "category": "ADV_1_5",
    "targets": {
      "age_ranges": [{"min": 25, "max": 44}],
      "geo_targets": {"country_code": "US"},
      "platforms": ["ANDROID", "DESKTOP", "IOS"],
      "placements": ["MUSIC"]
    },
    "bid_strategy": "MAX_BID",
    "bid_micro_amount": 15000000
  }' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/drafts/ad_sets"
```

**Expected curl (draft ad):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "ad_set_id": "<draft_ad_set_id>",
    "name": "[Test reject] Audio Draft Ad",
    "tagline": "...",
    "advertiser_name": "...",
    "assets": {
      "asset_id": "<uuid>",
      "logo_asset_id": "<uuid>",
      "companion_asset_id": "<uuid>"
    },
    "call_to_action": {
      "key": "LEARN_MORE",
      "clickthrough_url": "https://example.com"
    }
  }' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/drafts/ads"
```

**Success criteria:**
- All three entities created via `/drafts/` endpoints
- Draft ad set `campaign_id` references the draft campaign ID from step 3 (not a live campaign)
- Draft ad `ad_set_id` references the draft ad set ID from step 4 (not a live ad set)
- All schema quirks applied: micro-amounts, flat geo_targets, platform enums, bid_strategy as string, category present, companion_asset_id for AUDIO
- `call_to_action` uses `key` (not `type`) and `clickthrough_url` (not `url`)
- `draft_hierarchy_version` fetched fresh before validation
- Validation runs automatically after all drafts created
- Summary table shows all draft entity IDs

---

## Scenario 16: Edit a Draft Ad Set

**Prompt:** "Change the budget on that draft ad set to $150/day and expand targeting to ages 18-54"

**Quirks tested:** PATCH on draft ad set endpoint (not live ad set), micro-amount conversion, `draft_hierarchy_version` only on campaign entity

**Expected behavior:**
1. Agent identifies the draft ad set ID from prior context
2. Constructs PATCH to `/drafts/ad_sets/<id>` (NOT `/ad_sets/<id>`)
3. Converts $150 to 150000000 micro-amount
4. Updates age_ranges to `[{"min": 18, "max": 54}]`
5. Displays updated draft — note that `draft_hierarchy_version` is `null` on ad set responses (version only lives on the campaign entity)

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "budget": {"micro_amount": 150000000, "type": "DAILY"},
    "targets": {
      "age_ranges": [{"min": 18, "max": 54}],
      "geo_targets": {"country_code": "US"},
      "platforms": ["ANDROID", "DESKTOP", "IOS"],
      "placements": ["MUSIC"]
    }
  }' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/drafts/ad_sets/<draft_ad_set_id>"
```

**Success criteria:**
- Uses `/drafts/ad_sets/<id>` endpoint, NOT `/ad_sets/<id>`
- Budget converted to micro-amount: 150000000
- Age range updated correctly
- Response shows updated fields. `draft_hierarchy_version` is `null` on ad set draft responses — fetch the parent draft campaign to verify the version incremented
- Does NOT create a new draft — updates the existing one via PATCH

---

## Scenario 17: Validate a Draft Campaign

**Prompt:** `/spotify-ads-api:drafts validate <draft_campaign_id>`

**Quirks tested:** Two-step version fetch + validate, `draft_hierarchy_version` freshness, `VALIDATE` action, validation error display

**Expected behavior:**
1. Agent fetches draft campaign to get current `draft_hierarchy_version`
2. POSTs `{"action":"VALIDATE","draft_hierarchy_version":<version>}` to the draft campaign endpoint
3. Displays validation results

**Expected curl (fetch version):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/drafts/campaigns/<draft_campaign_id>"
```

**Expected curl (validate):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"action":"VALIDATE","draft_hierarchy_version":<version>}' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/drafts/campaigns/<draft_campaign_id>"
```

**Success criteria:**
- Version fetched via GET on the **draft campaign** before validation POST (not reused from earlier; `draft_hierarchy_version` is only populated on campaign drafts — ad set and ad drafts return `null`)
- `action` is `"VALIDATE"`, not `"PUBLISH"`
- `draft_hierarchy_version` in POST body matches the GET response
- On success (HTTP 200): `validation_errors` is `null` — displays "passed validation" and suggests publish
- On errors (HTTP 400): response body contains `validation_errors` array — displays each `HierarchyValidationError` with `validation_entity_type`, `validation_entity_id`, and `message`
- Suggests fix commands for each error

---

## Scenario 18: Publish a Draft Campaign

**Prompt:** `/spotify-ads-api:drafts publish <draft_campaign_id>`

**Quirks tested:** Pre-publish validation, explicit user confirmation even with `auto_execute: true`, version re-fetch immediately before publish, `PUBLISH` action

**Expected behavior:**
1. Agent fetches draft campaign to get `draft_hierarchy_version`
2. Runs validation first — if errors, stops and displays them
3. Shows the full hierarchy and asks for explicit confirmation
4. Re-fetches draft campaign immediately before publish to check version hasn't changed
5. If version changed since validation, re-validates before publishing
6. POSTs `{"action":"PUBLISH","draft_hierarchy_version":<version>}`
7. Displays published campaign details

**Expected curl (publish):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"action":"PUBLISH","draft_hierarchy_version":<version>}' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/drafts/campaigns/<draft_campaign_id>"
```

**Success criteria:**
- Validation runs BEFORE publish attempt
- If validation errors exist, publish is blocked — errors displayed instead
- User explicitly confirms before publish, even when `auto_execute` is true
- `draft_hierarchy_version` re-fetched immediately before publish POST
- If version changed between validation and publish, re-validates
- `action` is `"PUBLISH"`, not `"VALIDATE"`
- Response shows the published campaign (HTTP 200). Published entities retain the same IDs they had as drafts — no new UUIDs are generated
- Never auto-executes the PUBLISH request

---

## Scenario 19: Delete a Draft

**Prompt:** "Delete the draft campaign <unpublished_draft_campaign_id>"

**Quirks tested:** DELETE on draft endpoint (unlike live entities which use status changes), 204 response, cascade behavior

**Setup:** Use a separate unpublished throwaway draft campaign. Do not reuse a draft campaign that was already published in Scenario 18.

**Expected behavior:**
1. Agent identifies draft type and ID
2. Confirms deletion with user (cascade warning for campaigns)
3. Sends DELETE to `/drafts/campaigns/<id>`
4. Expects 204 No Content

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X DELETE -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/drafts/campaigns/<unpublished_draft_campaign_id>"
```

**Success criteria:**
- Uses DELETE method (drafts support DELETE, unlike live entities)
- Endpoint is `/drafts/campaigns/<id>`, NOT `/campaigns/<id>`
- Does NOT attempt status change (ARCHIVED/PAUSED) — those are for live entities
- Uses an unpublished draft fixture, not the draft published in Scenario 18
- Returns 204 No Content
- For draft campaigns: warns that associated draft ad sets and ads are also deleted
- DELETE is safe to retry (idempotent)

---

## Scenario 20: Create Draft from Published Entity

**Prompt:** "Create a draft from campaign <campaign_id> so I can make changes"

**Quirks tested:** `draft-from` endpoint path (entity ID in URL, not body), creates editable draft copy of live entity, parent draft campaign resolution for child drafts

**Expected behavior:**
1. Agent constructs POST to the appropriate create-from-published endpoint for campaign, ad set, or ad
2. Response includes a draft entity with the **same ID** as the live entity (not a new UUID), status `ACTIVE_RESTRICTED`
3. For campaign drafts, the returned ID is the draft campaign ID
4. For ad set drafts, agent uses the returned `campaign_id` as the draft campaign ID for validate/publish
5. For ad drafts, agent fetches the draft ad set referenced by `ad_set_id`, then uses that ad set's `campaign_id` as the draft campaign ID for validate/publish
6. Agent displays draft details and suggests next steps (edit, validate, publish)

**Expected curl (campaign):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/campaigns/<campaign_id>/drafts"
```

**Expected curl (ad set):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/ad_sets/<ad_set_id>/drafts"
```

**Expected curl (ad):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/ads/<ad_id>/drafts"
```

**Success criteria:**
- Endpoint is `/campaigns/<live_id>/drafts`, `/ad_sets/<live_id>/drafts`, or `/ads/<live_id>/drafts` with live entity ID in path
- Does NOT use `/drafts/campaigns`, `/drafts/ad_sets`, or `/drafts/ads` (those are for creating new drafts)
- Response includes a draft entity with the **same `id`** as the live entity (not a new UUID)
- Status becomes `ACTIVE_RESTRICTED`
- For child drafts, agent resolves the parent draft campaign ID before suggesting validate/publish commands
- `draft_hierarchy_version` may be `null` initially (no draft hierarchy edits yet)
- Agent suggests edit/validate/publish as next steps
- No request body required

---

## Scenario 21: Draft Validation Error Recovery

**Prompt:** Build a draft audio campaign that is intentionally missing `companion_asset_id` on the ad, then validate and fix

**Quirks tested:** Validation error display, edit to fix, re-validation cycle

**Setup:** Create a draft hierarchy (campaign + ad set + audio ad) but omit `companion_asset_id` from the ad's assets.

**Expected behavior:**
1. Draft hierarchy created (campaign, ad set, audio ad without `companion_asset_id`) — the draft create endpoint accepts incomplete data; validation only runs on explicit VALIDATE
2. Validation returns HTTP 400 with `validation_errors` array: `AD` entity missing `companion_asset_id` for AUDIO format
3. Agent displays error with entity type, ID, and message
4. User says "fix it" or provides the missing asset
5. Agent PATCHes the draft ad with the corrected `assets` object
6. Agent re-validates — this time validation passes (HTTP 200, `validation_errors: null`)
7. Asks user to publish or keep as draft

**Success criteria:**
- Draft ad creation succeeds without `companion_asset_id` (drafts accept incomplete data — this is the key benefit over direct creation)
- Validation catches the error with HTTP 400 (not 200) and `validation_errors` array
- Error display includes entity type (`AD`), entity ID, and descriptive message
- Fix uses PATCH on `/drafts/ads/<id>` (not creating a new draft ad)
- Re-validation uses fresh `draft_hierarchy_version` from the draft campaign (not the version from before the edit; `draft_hierarchy_version` is `null` on ad drafts)
- Full cycle: create → validate (fail @ 400) → edit → validate (pass @ 200) → offer publish
