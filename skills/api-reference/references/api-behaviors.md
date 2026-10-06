# Spotify Ads API v3 — Runtime Behaviors

The live OpenAPI document is the source of truth for paths, parameters, field names, types, required flags, and enum values. Follow `live-openapi.md` before the first call in every workflow. This file records only behavior the spec cannot express. When it and the live spec disagree on contract details, the spec wins.

## Money and Micro-Amounts

- Budget and bid values in entity and estimate payloads are micro-units: 1 unit of the ad account's billing currency = 1,000,000 micro-units (e.g., $15 USD = `15000000`, ¥160 JPY = `160000000`).
- Estimate monetary outputs (CPM ranges, bid suggestions) and `reserved_prices` `cost_micro` are also micro-units. Divide by 1,000,000 for display.
- `SPEND` values returned by `aggregate_reports` are already in the billing currency. Do NOT divide them by 1,000,000.

## Reserved Pricing and Forecasting

Use this flow for `CONTENT` (Reserved Podcasts) and `FPMNG` (Reserved Music):

1. Call `POST /ad_accounts/{ad_account_id}/reserved_prices` with the planned product, dates, format, and targeting. Use the same product, dates, format, and targeting in the forecast. The response's `cost_micro / 1,000,000` is the fixed CPM in the returned currency.

   ```bash
   api POST "ad_accounts/{ad_account_id}/reserved_prices" '<body built from the live spec>'
   ```

2. When the plan specifies desired impressions rather than a budget, the planned total budget in micros is `cost_micro * desired_impressions / 1,000`. For example, `cost_micro` `10000000` and 100,000 impressions gives `1000000000` ($1,000 USD).
3. Read the live request contract for `POST /estimates/audience` and the live `GET /ad_product_catalog` rules for the product before building the forecast or ad set. Use the fetched `cost_micro` as `bid_micro_amount` in both the forecast and the ad set, and the returned currency in the forecast budget. Resolve objective, bid strategy, budget type, delivery goal, targeting, and other product-specific fields from those live sources; do not apply auction defaults to a Reserved buy.
4. Apply the live catalog rules (`ad-product-validation.md`) to the final campaign and ad set payloads before creating or editing them.
5. Report the fixed rate separately from forecast reach, impressions, estimated CPM, and bid suggestions. A zero forecast CPM or bid suggestion is not a zero fixed rate and does not explain itself. If pricing fails, report the rate as unavailable; never invent a price or forecast with a fabricated bid.

## Estimates

- `POST /estimates/audience` and `POST /estimates/bid` are top-level paths, not nested under `/ad_accounts/{ad_account_id}/`. Pass the ad account in the body where the spec asks for it.
- Build every estimate body from the live spec and include every field it marks as required. Treat a field as required when either its schema's `required` list names it or its description says it is required. For example, the spec marks `targets.placements` as required only in description text. Always set `placements` on audience estimates and ad sets, taking the values from the live spec and catalog. The estimate budget shape can differ from the ad set budget; check each separately.
- The AUTOBID exception (omitting `bid_micro_amount`) applies only to ad set payloads. Never omit a bid from an estimate on the basis of AUTOBID. For auction buys, use the planned bid cap. For Reserved buys, use `cost_micro`.
- `audience_forecast` holds up to three entries (daily, weekly, monthly) for a DAILY budget and a single LIFETIME entry for a LIFETIME budget. `raw_unique_users` is the exact count of matching users over the past 7 days. `projected_unique_users` is that audience adjusted for frequency caps and budget, so report it as the expected reach.
- Run an audience estimate before creating each ad set (direct or draft) to catch targeting problems early.
- **"Min audience threshold was not met" (400)** means the targeting is too narrow. Never resend the same request, and never widen targeting yourself. Report the narrow audience, suggest broader options along with any `bid_suggestion`, ask the user how to broaden it, then re-estimate with their choice. Offer "proceed anyway" only when an estimate came back valid but low, never after a threshold 400.

## Targeting

- Never fall back to country-only targeting without first looking up the user's requested location. Resolve it with `GET /targets/geos?country_code=<code>&q=<query>` and use the returned IDs in the matching refinement array of the geo target object.
- Geo lookup returns `REGION`, `DMA_REGION`, `CITY`, and `POSTAL_CODE` results. DMA-level targeting is not supported. Treat `DMA_REGION` results as informational only, and suggest regions or cities instead.
- In the interest targets response, the `interests` key is always null. Use `interests_with_subtargets`. Both parent and subtarget IDs are valid interest IDs.
- Among the targeting lookups, only `/targets/geos` paginates with `limit`/`offset`. Genre and interest lookups return everything in one response and reject `limit`, `offset`, or any unlisted parameter with a 400. Check the live spec before adding paging to any other lookup.
- `category` on ad sets must be a valid code from `GET /ad_categories`. Look it up instead of guessing.

## Reporting

- The metrics query parameter is `fields`. Array query parameters use repeated names (`fields=IMPRESSIONS&fields=SPEND`), not comma-separated values.
- In `aggregate_reports`, `entity_status_type` must match `entity_type` (e.g., both `AD_SET`). A mismatch causes a filter validation error.
- Aggregate report date ranges must be within 90 days for `LIFETIME` and `DAY`, and within the last 2 weeks for `HOUR`. `aggregate_reports/totals` accepts at most 50 entity IDs per request and does not support `HOUR` granularity. Split larger sets into batches.
- Aggregate, insight, and async CSV reports have separate metric vocabularies. Do not reuse names across them. Check the live enum for the specific endpoint.
- Insight reports can return 422 when an ad has not delivered enough activity. Poll no more than once per day, and stop about two weeks after the ad's end date.

## Drafts

- Create the hierarchy as drafts (campaign, then ad sets referencing the draft campaign, then ads referencing the draft ad set), validate it, and publish only after review.
- VALIDATE and PUBLISH share one handler: `POST /ad_accounts/{ad_account_id}/drafts/campaigns/{draft_id}` with the action and current `draft_hierarchy_version`.
  - HTTP 200 means success (`validation_errors` is null).
  - Hierarchy validation errors return HTTP 400 with a `PublishCampaignResult` whose `validation_errors` list identifies the entity type, entity ID, message, and error codes. On a 400, check for `validation_errors` first and show them. Otherwise treat it as any other error. Never retry automatically.
  - Fix with PATCH on the draft entities, then re-validate.
- `draft_hierarchy_version` is populated only on the draft campaign (ad set and ad drafts return null). It increments whenever any entity in the hierarchy is created or edited. Refetch the draft campaign immediately before every VALIDATE or PUBLISH. Never reuse a version captured before child creation or edits.
- PUBLISH creates live entities with the same IDs. Ask the user to confirm immediately before publishing, even when `auto_execute` is true.
- Draft entities can be deleted. Draft DELETE returns 204 and is safe to retry.
- Create-from-published (`POST .../campaigns/{id}/drafts`, and likewise for ad sets and ads) makes a draft copy that reuses the same entity `id` (not a new UUID), and its status becomes `ACTIVE_RESTRICTED`.

## Live Entity Lifecycle

- There is no DELETE on live campaigns, ad sets, or ads. Use status changes (`PAUSED`, `ARCHIVED`).
- Archived creatives cannot be edited.

## Errors and Retry Safety

- Error bodies are based on the live spec's error response schema: `messages`, a list of error codes (each with a `code` and a `definition` that suggests a fix), and `sp_trace_id`. Live responses do not always use the spec's casing for the error-code key. Read `messages` and whichever error-code key is present, without depending on one spelling. Show the messages and codes to the user, and always surface `sp_trace_id`. Check the live spec for endpoint-specific error shapes, such as `validation_errors` on draft publish.
- Common statuses: 400 validation error, 403 insufficient permissions, 404 not found, 422 unprocessable (e.g., insufficient insight data), 500 server error.
- Check the wrapper's `HTTP_STATUS:` line first.
- Retry only on network errors or 5xx, and only for idempotent methods (GET). Never retry a POST or PATCH automatically. A non-timeout 4xx means the request was received and rejected. A 5xx may mean the change was already applied, so check for the created or modified resource before suggesting a retry. For creates, follow `create-retry-safety.md`.
