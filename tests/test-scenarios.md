# Test Scenarios

34 structured test scenarios for validating the Spotify Ads API plugin. Each scenario covers specific API quirks and plugin behaviors. For a concise prompt-per-capability view, see [`prompt-catalog.md`](prompt-catalog.md).

**Important:** All entity names (campaigns, ad sets, ads) must be prefixed with `[Test reject]` so they are automatically rejected by ad review and never serve live impressions.

---

**Variables used in curl examples below:**
- `$TOKEN` — OAuth access token from settings
- `$BASE_URL` — `https://api-partner.spotify.com/ads/v3`
- `$SDK_HEADER` — `X-Spotify-Ads-Sdk: $SDK_PRODUCT/$PLUGIN_VERSION`, where `SDK_PRODUCT` is `codex-plugin` on Codex, `claude-code-plugin` on Claude, and `antigravity-cli-plugin` on Antigravity
- `$SKILL_HEADER` — `X-Spotify-Ads-Skill: <skill-name>`

The expanded curl snippets below describe the HTTP contract. The plugin should normally execute the equivalent request through `scripts/api-request.sh`, which adds authentication, both tracking headers, and `HTTP_STATUS:` capture. Raw curl is reserved for documented upload and OAuth exceptions.

---

## Scenario 1: Configure OAuth

**Prompt:** `/spotify-ads-api:configure` (`/configure` on Antigravity)

**Quirks tested:** OAuth flow, settings file creation, token validation

**Expected behavior:**
1. Plugin prompts for `client_id` and `client_secret`
2. Runs `oauth-flow.py` to open browser and complete authorization
3. Parses JSON output with `access_token`, `refresh_token`, `expires_in`
4. Prompts for `ad_account_id`, `auto_execute`
5. Stores `client_secret` in the macOS Keychain and writes the non-secret fields to the active platform settings file (`.codex/spotify-ads-api.local.md` on Codex, `.claude/spotify-ads-api.local.md` on Claude, `.agents/spotify-ads-api.local.md` on Antigravity)
6. Verifies token with test API call

**Success criteria:**
- Settings file exists with all YAML fields populated
- `token_expires_at` is a valid ISO 8601 timestamp in the future
- Test API call returns 200
- The settings file does not contain `client_secret`
- Access tokens and the client secret are never displayed after capture

---

## Scenario 2: List Campaigns

**Prompt:** "Show me all my campaigns"

**Quirks tested:** GET with pagination, auto_execute behavior

**Expected behavior:**
1. Agent reads settings file
2. Uses the request wrapper to call `GET ad_accounts/{ad_account_id}/campaigns?limit=50&sort_direction=DESC`; the wrapper supplies authorization, SDK/skill headers, and status capture
3. If `auto_execute` is false, shows command and asks for confirmation
4. Formats response as table: ID | Name | Status | Objective | Created

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/campaigns?limit=50&sort_direction=DESC"
```

**Success criteria:**
- Returns 200 with campaigns list or empty array
- Output formatted as readable table
- Token is masked in displayed command

---

## Scenario 3: Create Campaign

**Prompt:** "Create a campaign called [Test reject] Q1 Brand Awareness with a reach objective"

**Quirks tested:** Draft-first creation, POST body construction, goal mapping, `[Test reject]` prefix for automatic ad review rejection

**Expected behavior:**
1. Agent extracts the name and maps the reach goal to `delivery_goal_group="AWARENESS"`
2. Constructs a draft campaign POST request with JSON body
3. Shows the `api()` helper request for confirmation
4. Reports the campaign as staged and does not publish it

**Expected API helper call:**
```bash
api POST "ad_accounts/{ad_account_id}/drafts/campaigns" \
  '{"name":"[Test reject] Q1 Brand Awareness","delivery_goal_group":"AWARENESS"}'
```

**Success criteria:**
- Request body contains exactly `name` and `delivery_goal_group`
- `name` starts with `[Test reject]`
- Delivery goal group is the uppercase enum value `AWARENESS`; deprecated `objective` is omitted
- Returns a draft campaign object including `id` and `draft_hierarchy_version`
- Does not call the published `/campaigns` creation endpoint
- Does not publish without a separate request and explicit confirmation

---

## Scenario 4: Create Ad Set with Targeting

**Prompt:** "Create an ad set for that campaign targeting 18-34 year olds in the US on mobile and desktop with a $75/day budget and $20 bid cap"

**Quirks tested:**
- Draft ad set creation under the draft campaign from Scenario 3
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

**Expected API helper call:**
```bash
api POST "ad_accounts/{ad_account_id}/drafts/ad_sets" '{
    "name": "[Test reject] ...",
    "campaign_id": "<campaign_id>",
    "start_time": "<FUTURE_START_TIME_UTC>",
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
  }'
```

**Success criteria:**
- `geo_targets` is `{"country_code": "US"}`, NOT `[{"country_code": "US"}]`
- `platforms` contains `ANDROID`/`IOS`/`DESKTOP`, NOT `MOBILE`
- `bid_strategy` is string `"MAX_BID"`, NOT `{"type": "MAX_BID"}`
- Budget is `75000000`, not `75`
- `bid_micro_amount` is `20000000`, not `20`
- `category` is present and matches `ADV_*` pattern
- `placements` array is present
- `campaign_id` references the draft campaign from Scenario 3
- Does not call the published `/ad_sets` creation endpoint

---

## Scenario 5: Create Audio Ad

**Prompt:** "Create an audio ad for that ad set with a Shop Now button linking to example.com"

**Quirks tested:**
- Draft ad creation under the draft ad set from Scenario 4
- `call_to_action` uses `key` (not `type`) and `clickthrough_url` (not `url`)
- `companion_asset_id` required for AUDIO format
- Asset selection flow

**Expected behavior:**
1. Agent fetches available assets from `GET /assets`
2. Prompts user to select `asset_id` (audio), `logo_asset_id` (image), `companion_asset_id` (image)
3. Sets `call_to_action.key` to `"SHOP_NOW"` (not `type`)
4. Sets `call_to_action.clickthrough_url` to the URL (not `url`)

**Expected API helper call:**
```bash
api POST "ad_accounts/{ad_account_id}/drafts/ads" '{
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
  }'
```

**Success criteria:**
- `call_to_action` has `key` field, NOT `type`
- `call_to_action` has `clickthrough_url` field, NOT `url`
- `companion_asset_id` is present in `assets`
- All three asset IDs are populated
- `ad_set_id` references the draft ad set from Scenario 4
- Fetches the parent draft campaign's current hierarchy version and validates the hierarchy after the draft ad is complete
- Does not publish without a separate request and explicit confirmation

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
- Draft campaign created with `delivery_goal_group` (default `AWARENESS`, not deprecated `objective`) and `[Test reject]` prefix in name
- Draft ad set created with all required fields (budget 100000000, geo_targets flat, platforms correct, category present, placements present, bid_strategy as string) and `[Test reject]` prefix in name
- Draft ad created with all required assets (including companion_asset_id for AUDIO) and `[Test reject]` prefix in name
- Draft IDs correctly passed from each step to the next
- `draft_hierarchy_version` fetched fresh before validation (not reused from creation response)
- Validation runs automatically after all drafts are created
- If user requests publish, explicit confirmation is required even with `auto_execute: true`

**Note:** If the user explicitly says "skip drafts" or "create live entities", the agent should use direct endpoints instead.

---

## Scenario 7: Pull Aggregate Report

**Prompt:** "Show me impressions, spend, and clicks for all campaigns last month"

**Quirks tested:**
- `fields` as repeated params (`&fields=X&fields=Y`), NOT comma-separated
- Field name is `fields`, NOT `report_fields`
- Date range calculation
- SPEND unit handling (aggregate-report values are already in account currency)

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/aggregate_reports?\
entity_type=CAMPAIGN&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&\
granularity=DAY&\
report_start=<PREVIOUS_MONTH_START_UTC>&\
report_end=<PREVIOUS_MONTH_END_UTC>&\
limit=50"
```

**Success criteria:**
- Query parameter is `fields`, NOT `report_fields`
- Fields use repeated parameter format: `fields=IMPRESSIONS&fields=SPEND&fields=CLICKS`
- NOT comma-separated: `fields=IMPRESSIONS,SPEND,CLICKS` (WRONG)
- Date range is computed as the previous calendar month using valid UTC-midnight boundaries
- SPEND is formatted as currency without dividing by 1,000,000

---

## Scenario 8: Pause a Campaign

**Prompt:** "Pause the [Test reject] Q1 Brand Awareness campaign"

**Quirks tested:** Implicit draft routing for a status change; no live PATCH or DELETE

**Expected behavior:**
1. Agent searches for campaign by name (GET with filter or list and match)
2. Checks for an existing same-ID campaign draft
3. If none exists, creates one from the published campaign
4. PATCHes the draft campaign with `{"status": "PAUSED"}`
5. Fetches the current draft hierarchy version and validates the staged change
6. Does not publish automatically

**Expected API helper calls:**
```bash
api POST "ad_accounts/{ad_account_id}/campaigns/<campaign_id>/drafts"
api PATCH "ad_accounts/{ad_account_id}/drafts/campaigns/<campaign_id>" \
  '{"status":"PAUSED"}'
```

**Success criteria:**
- Creates or reuses a same-ID draft before PATCH
- PATCHes `/drafts/campaigns/<id>`, NOT `/campaigns/<id>`
- Body contains `{"status": "PAUSED"}`
- Does not try to call a DELETE endpoint
- Validates the parent draft campaign and reports the pause as staged
- Does not publish automatically

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
  -H "$SKILL_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "daily_impressions_spend_previous_month",
    "granularity": "DAY",
    "dimensions": ["CAMPAIGN_NAME"],
    "metrics": ["IMPRESSIONS_ON_SPOTIFY", "SPEND"],
    "report_start": "<PREVIOUS_MONTH_START_UTC>",
    "report_end": "<PREVIOUS_MONTH_END_UTC>"
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
Edit the active platform settings file (`.codex/spotify-ads-api.local.md` on Codex, `.claude/spotify-ads-api.local.md` on Claude, `.agents/spotify-ads-api.local.md` on Antigravity) and set `token_expires_at` to any valid timestamp in the past. Ensure `refresh_token` and `client_id` are populated and the client secret exists in the macOS Keychain. The settings file must not contain `client_secret`.

**Expected behavior:**
1. User runs a command (e.g., "Show me all campaigns")
2. The pre-tool hook (`PreToolUse` on Claude/Codex/Antigravity) detects the curl targets `api-partner.spotify.com`
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
  -H "$SKILL_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"asset_type":"AUDIO","name":"my-creative"}' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/assets"
```

**Expected curl (upload):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
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
2. Plugin calls `GET /targets/geos?country_code=US&q=Portland` and resolves ambiguity among matching cities or regions with the user
3. After user confirms the plan, runs `POST /estimates/audience` using the selected geo ID
4. Endpoint is top-level: `https://api-partner.spotify.com/ads/v3/estimates/audience` (NOT under `/ad_accounts/{id}/`)
5. Displays audience estimate (projected users, reach, impressions, CPM)
6. If audience is too small (likely with VIDEO + narrow age + single city), warns user
7. Suggests: broaden age range, add platforms, switch to AUDIO, expand geo
8. Asks whether to proceed, adjust, or cancel

**Expected curl (estimate):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "ad_account_id": "<account_id>",
    "start_date": "<FUTURE_START_TIME_UTC>",
    "asset_format": "VIDEO",
    "objective": "REACH",
    "bid_strategy": "MAX_BID",
    "bid_micro_amount": 15000000,
    "budget": {"micro_amount": 25000000, "type": "DAILY", "currency": "USD"},
    "targets": {
      "age_ranges": [{"min": 50, "max": 54}],
      "geo_targets": {"country_code": "US", "city_ids": ["<selected_portland_city_id>"]},
      "platforms": ["ANDROID", "DESKTOP", "IOS"],
      "placements": ["MUSIC"]
    }
  }' \
  "https://api-partner.spotify.com/ads/v3/estimates/audience"
```

**Success criteria:**
- Audience estimate runs BEFORE ad set creation (not after)
- Endpoint is top-level `/estimates/audience`, NOT under `/ad_accounts/{id}/`
- The selected Portland geo ID is included; the plugin does not silently fall back to US-only targeting
- Warning displayed when audience is too small
- User given options to proceed, adjust, or cancel
- If user adjusts targeting, estimate re-runs with new parameters

---

## Scenario 13: Dashboard

**Prompt:** `/spotify-ads-api:dashboard`

**Quirks tested:** Aggregate SPEND unit handling, aggregate report field format, active campaign filtering, zero-impression filtering

**Expected behavior:**
1. Plugin fetches aggregate report for active campaigns (entity_type=CAMPAIGN, statuses=ACTIVE)
2. Uses repeated `fields` parameters (`&fields=IMPRESSIONS&fields=SPEND&...`), NOT comma-separated
3. Fetches campaign details for names and budget info
4. Displays formatted table with campaign metrics
5. Spend values are treated as billing-currency units and formatted without micro-unit conversion
6. Rows with zero impressions are filtered out
7. Shows pacing info when budget data is available

**Expected curl (metrics):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/aggregate_reports?\
entity_type=CAMPAIGN&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&fields=FREQUENCY&fields=CTR&fields=COMPLETES&\
granularity=LIFETIME&\
entity_status_type=CAMPAIGN&\
statuses=ACTIVE&\
limit=50"
```

**Success criteria:**
- For a USD account, a returned SPEND value of `450` is displayed as `$450.00`, not `$0.00045`; other accounts use their configured billing currency
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
  -H "$SKILL_HEADER" \
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
  -H "$SKILL_HEADER" \
  -H "Content-Type: application/json" \
  -d '{"name":"[Test reject] Audio Draft Campaign","delivery_goal_group":"AWARENESS"}' \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/drafts/campaigns"
```

**Expected curl (draft ad set):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  -H "Content-Type: application/json" \
  -d '{
    "campaign_id": "<draft_campaign_id>",
    "name": "[Test reject] Audio Draft Ad Set",
    "start_time": "<FUTURE_START_TIME_UTC>",
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
  -H "$SKILL_HEADER" \
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
3. Converts $150 to 150000000 micro-amount (amount in the ad account's billing currency)
4. Updates age_ranges to `[{"min": 18, "max": 54}]`
5. Displays updated draft — note that `draft_hierarchy_version` is `null` on ad set responses (version only lives on the campaign entity)

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X PATCH -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
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
  -H "$SKILL_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/drafts/campaigns/<draft_campaign_id>"
```

**Expected curl (validate):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
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
  -H "$SKILL_HEADER" \
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
  -H "$SKILL_HEADER" \
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

**Prompt:** "Create a draft from campaign <published_campaign_id> so I can make changes"

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
  -H "$SKILL_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/campaigns/<campaign_id>/drafts"
```

**Expected curl (ad set):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/ad_sets/<ad_set_id>/drafts"
```

**Expected curl (ad):**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -X POST -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
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

---

## Scenario 22: Campaign Strategy Without Creation

**Prompt:** “Plan the best Spotify campaign structure for this landing page and a $5,000 launch budget. Do not create anything.”

**Quirks tested:** Strategy routing, source-grounded recommendations, target validation, non-mutating POST estimates, planning boundary

**Expected behavior:**
1. Routes to `campaign-strategy` and inspects the supplied page or brief.
2. Proposes objectives, ad sets, targeting, budget split, bids, formats, and creative rotation with stated assumptions.
3. Looks up requested geographies and available targets instead of inventing IDs.
4. Runs audience and bid estimates when credentials are available; these POSTs are planning calls, not entity creation.
5. Presents an API-ready plan and does not create campaigns, ad sets, ads, drafts, or assets.

**Success criteria:**
- Recommendations are traceable to the supplied source and current target availability.
- Each proposed ad set has required fields and a defensible budget/bid.
- No entity-creation endpoint is called.
- The user is offered a separate next step to build the approved plan.

---

## Scenario 23: Read-Only Campaign Health Monitor

**Prompt:** “Which active campaigns are underpacing, stalled, or close to exhausting their budgets?”

**Quirks tested:** Monitor routing, status filtering, campaign/ad-set report joins, SPEND units, health thresholds

**Expected behavior:**
1. Routes to `monitor` and fetches active campaigns and ad sets.
2. Pulls campaign and ad-set aggregate reports with repeated `fields` parameters.
3. Uses `entity_status_type=CAMPAIGN` for campaign reports and `entity_status_type=AD_SET` for ad-set reports.
4. Treats returned SPEND as billing-currency units, calculates pacing, and explains each warning.
5. Makes no status or budget changes.

**Success criteria:**
- Every warning identifies the entity, evidence, severity, and suggested follow-up.
- Zero delivery, end-date risk, budget exhaustion, and underpacing are distinguished.
- The run is entirely read-only.

---

## Scenario 24: Bulk Budget Preview and Partial Failure

**Prompt:** “Increase the daily budgets of every active ad set in `[Test reject] Bulk fixture` by 10%.”

**Quirks tested:** Exact selection, percentage micro-amount math, preview/confirmation, sequential PATCH, partial-failure handling

**Expected behavior:**
1. Resolves the campaign and lists its active ad sets.
2. Shows old and proposed budgets for every selected ID, preserving budget type and currency.
3. Requires confirmation after the complete batch preview.
4. Applies PATCH requests sequentially and does not retry failures automatically.
5. Continues after an individual failure and reports succeeded, failed, and skipped entities.

**Success criteria:**
- A `50000000` daily micro-amount becomes `55000000`, with correct rounding for other values.
- No unlisted ad set is modified.
- One confirmation covers the exact displayed batch; changed selection requires a new preview.
- Partial failures do not hide successful updates or trigger retries.

---

## Scenario 25: Clone a Campaign Safely

**Prompt:** “Clone campaign `<campaign_id>` for next month, add `Copy` to every name, and keep the same targeting and creative.”

**Quirks tested:** Full source traversal, relative date shifting, asset validation, audience estimates, ID remapping, confirmation

**Expected behavior:**
1. Reads the source campaign, all child ad sets, and all child ads.
2. Displays the source hierarchy and proposed changes.
3. Validates referenced assets and runs audience estimates for proposed ad sets.
4. Omits source IDs, statuses, metrics, timestamps, and other read-only fields from create bodies.
5. Copies `delivery_goal_group`, or maps a legacy source `objective` to it, without sending deprecated `objective` on the new draft campaign.
6. Requires confirmation, then creates the new hierarchy in dependency order and maps new parent IDs.

**Success criteria:**
- “Next month” is calculated at run time and each flight retains its intended duration.
- The source hierarchy is unchanged.
- New ads point to new ad-set IDs, not source IDs.
- Failed POSTs are checked for possible creation before any retry is proposed.

---

## Scenario 26: Denormalized CSV Export

**Prompt:** “Export campaigns, ad sets, ads, targeting, budgets, and last-30-day metrics to `<output_path>`.”

**Quirks tested:** Pagination, cross-entity joins, repeated report fields, SPEND units, file scope

**Expected behavior:**
1. Routes to `export`, confirms entity/metric/date preferences, and resolves the exact output path.
2. Paginates campaigns, ad sets, and ads.
3. Fetches metrics at the requested level using valid DAY boundaries.
4. Joins rows by entity IDs, denormalizes nested targeting, and writes one CSV.
5. Reports row count, date range, included levels, and output path.

**Success criteria:**
- Parent names and IDs remain correctly associated with every row.
- Budget micro-amounts are converted to currency; aggregate SPEND is not divided again.
- CSV quoting preserves commas and nested values.
- No files other than the requested export are written.

---

## Scenario 27: Customer-List Audience Upload

**Prompt:** “Upload `<synthetic_customer_csv>` and create an audience named `[Test] Synthetic CRM`.”

**Quirks tested:** Privacy guardrail, signed GCS resumable upload, upload ID handoff, non-retry behavior

**Expected behavior:**
1. Confirms the file exists without printing or summarizing its contents.
2. Requests `POST /ad_accounts/{id}/audiences/upload_url` and captures both `id` and `upload_url`.
3. Initiates the signed GCS upload with POST plus `x-goog-resumable: start`, captures the `Location` session URI, then PUTs the file to that URI.
4. Sends no Ads API authorization or tracking headers to either signed GCS URL.
5. Creates the `CUSTOM` / `CUSTOMER_LIST` audience using the returned upload ID.

**Success criteria:**
- The fixture contains invented test data only and its rows never appear in output.
- A missing session URI stops the flow before file upload or audience creation.
- Ambiguous POST or PUT failures are not automatically retried.
- The resulting audience ID and processing status are displayed.

---

## Scenario 28: Pixel and CAPI Topology Plan

**Prompt:** “Design Pixel and CAPI purchase tracking with deduplication. Show the plan, but do not create tokens or send events.”

**Quirks tested:** Measurement intake, event mapping, dataset creation order, mutation boundaries, secret handling

**Expected behavior:**
1. Routes to `measurement-setup` and asks about business/ad account, web/app surface, events, identifiers, consent, environments, and ownership.
2. Defines a shared `event_id` strategy for duplicate Pixel/CAPI representations of the same purchase.
3. Plans Pixel creation first, then CAPI creation with `dataset_id` pointing to the Pixel’s auto-created dataset.
4. Plans dataset sharing to the selected ad account and documents implementation requirements.
5. Stops before creating resources, tokens, or synthetic conversion events.

**Success criteria:**
- The plan does not combine independently created integrations with a multi-ID `POST datasets` request.
- Pixel `value` and CAPI `event_details.amount` are not conflated.
- PII and CAPI secrets are absent from examples and output.
- Configuration is not presented as proof of attribution.

---

## Scenario 29: Read-Only Measurement Incident Triage

**Prompt:** “CAPI purchases stopped yesterday for dataset `<dataset_id>`. Audit the setup read-only.”

**Quirks tested:** Topology-first diagnosis, diagnostics granularity, dataset routing, ingestion-versus-attribution boundary

**Expected behavior:**
1. Resolves the business, CAPI integration, dataset, and ad-account sharing; retrieves token inventory only when authentication is in scope and redacts the secret-bearing response.
2. Checks each integration’s `dataset_id` and flags a null or mismatched link.
3. Pulls hourly and daily dataset diagnostics and compares last activity by datasource.
4. Separates ingestion, selection, attribution, and reporting explanations.
5. Produces findings and a remediation plan without sending events or changing resources.

**Success criteria:**
- Secrets and personal identifiers are neither requested nor displayed.
- Pixel-list 403 and dataset-list pagination limitations are handled as documented.
- No POST, PATCH, or DELETE is made.
- Any proposed test event is clearly separated and requires later explicit confirmation.

---

## Scenario 30: Account Access Removal Boundary

**Prompt:** “Remove `<member_id>` from ad account `<ad_account_id>`.”

**Quirks tested:** Identity resolution, blast-radius display, caller protection, explicit destructive confirmation

**Expected behavior:**
1. Routes to `account-admin` and fetches the exact account and member.
2. Displays the member identity, current role, account, and effect of removal.
3. Detects whether the target is the caller and refuses to infer self-removal intent.
4. Requires explicit confirmation immediately before `DELETE /ad_accounts/{ad_account_id}/members/{member_id}`.
5. Verifies the result with a read-only follow-up.

**Success criteria:**
- Name-only ambiguity is resolved before confirmation.
- No business-wide removal endpoint is substituted for account-only removal.
- `auto_execute=true` does not bypass confirmation.
- A failed DELETE is not automatically retried.

---

## Scenario 31: API Reference and Invalid-Shape Probe

**Prompt:** “What fields are required for an audio ad set and ad? Show the schema and enums only; do not call the API.”

**Quirks tested:** Reference routing, no-execution constraint, critical schema quirks

**Expected behavior:**
1. Routes to `api-reference` and answers from the committed API documentation/spec.
2. Identifies required ad-set category, placements, flat `geo_targets`, valid platforms, and bid strategy shape.
3. Identifies `call_to_action.key`, `clickthrough_url`, and required AUDIO `companion_asset_id`.
4. Makes no network or Ads API call.

**Success criteria:**
- `bid_strategy` is described as a string enum, not an object.
- `MOBILE` and `CONNECTED_DEVICE` are rejected as platform values.
- Array query parameters are described as repeated names.
- The response distinguishes documented facts from any examples or recommendations.

---

## Scenario 32: Change History

**Prompt:** "Show me all budget changes in the last 7 days"

**Quirks tested:** change_category filter, date range calculation, timeline display, before/after field diffs

**Expected behavior:**
1. Agent calculates `created_gte` as 7 days ago in ISO 8601
2. Constructs GET with `change_category=BUDGET` and `created_gte` filter
3. Formats response as timeline: Timestamp | Entity Type | Entity Name | Operation | Actor | Changes

**Expected curl:**
```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer <token>" \
  -H "$SDK_HEADER" \
  "https://api-partner.spotify.com/ads/v3/ad_accounts/<account_id>/change_history?\
change_category=BUDGET&\
created_gte=2026-07-28T00:00:00Z&\
limit=50&\
sort_direction=DESC"
```

**Success criteria:**
- Endpoint is `/ad_accounts/{id}/change_history` (underscore, not hyphen)
- `change_category` uses valid enum: `BUDGET` (not `CREATED` — that is an `operation`, not a category)
- Date range correctly calculated from "last 7 days"
- Before/after values displayed for CHANGED operations (e.g., budget was $50/day → $75/day)
- Micro-amount budget values converted to the billing currency for display
- Actor name shown (not just principal_id)
- Returns 200 with change records or empty array
- If empty, displays "No budget changes found in the last 7 days"

---

## Scenario 33: Implicit Draft Tracking Update

**Prompt:** "Update the third-party tracking on these five published ads: remove tracker X, add impression tracker Y, update click tracker Z, and remove unsupported macros."

**Quirks tested:** Natural-language edit routing without the word "draft", same-ID draft reuse, complete tracking-array preservation, parent campaign grouping, batch validation

**Expected behavior:**
1. Agent reads each published ad and its current `third_party_tracking` array.
2. For each ad, checks `GET /drafts/ads/<ad_id>` before creating anything.
3. Reuses and discloses an existing draft, or calls `POST /ads/<ad_id>/drafts` only after a 404.
4. Constructs the complete intended tracking array, preserving entries the user did not request to remove or replace.
5. Sets `measurement_event` explicitly on every tracker, including `CLICKED` for the click tracker and `IMPRESSION` for impression trackers.
6. PATCHes `/drafts/ads/<ad_id>`, never the published `/ads/<ad_id>` endpoint.
7. Groups the draft ads by parent draft campaign and validates once per affected campaign using a freshly fetched `draft_hierarchy_version`.
8. Reports the updates as staged and does not publish them.

**Expected API helper pattern for each ad:**

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" bulk "$@"; }

api GET "ad_accounts/{ad_account_id}/drafts/ads/<ad_id>"
api POST "ad_accounts/{ad_account_id}/ads/<ad_id>/drafts"
api PATCH "ad_accounts/{ad_account_id}/drafts/ads/<ad_id>" \
  '{"third_party_tracking":[...]}'
```

The create-from-published POST is omitted when the initial draft GET succeeds.

**Success criteria:**
- The prompt does not need to contain the word "draft".
- No `PATCH /ads/<ad_id>` published endpoint is called.
- Existing drafts are disclosed and preserved rather than overwritten.
- Tracking entries use `measurement_event`, not `type`.
- Validation runs once per affected parent campaign after all successful patches are staged.
- Nothing is published without a separate request and explicit confirmation.

---

## Scenario 34: Direct Write Permission Denial

**Prompt:** "Update published ad <ad_id> directly right now" followed by a direct-write HTTP 403 edit-permission response

**Quirks tested:** Explicit live-write escape hatch, narrow permission-error interpretation, draft fallback offer

**Expected behavior:**
1. Because the user explicitly requested a direct published change, the agent may use the live endpoint.
2. On HTTP 403, it does not retry the POST or PATCH.
3. It says that direct editing of the published entity was denied.
4. It does not claim that the credentials or account are entirely read-only.
5. It offers to stage the same change through the draft workflow.
6. It does not silently create a draft because the user explicitly requested an immediate live change.

**Success criteria:**
- No retry of the failed direct write.
- No inference about specific organizational roles, user types, tools, or permission systems.
- No recommendation to use a proprietary UI or ask a specially privileged user.
- Draft staging is presented as the compatible alternative in generic, public-facing language.
