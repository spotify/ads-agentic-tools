---
name: campaign-strategy
description: Generate Spotify Ads campaign strategy from a landing page, product or business page, brand brief, location page, uploaded creative assets, existing Spotify Ads assets, or a natural-language business goal. Use when the user asks for the best campaign structure, targeting plan, audience plan, budget split, creative rotation, API-ready campaign plan, or pre-build recommendations before creating Spotify campaigns.
---

# Spotify Ads API - Campaign Strategy

Plan campaign structure and targeting before creating entities. This skill researches the offer, checks current Spotify Advertising guidance, validates targetability through the Ads API, and returns an API-ready plan. Do not create campaigns, ad sets, ads, assets, or audiences unless the user explicitly asks to execute after reviewing the plan.

For detailed planning heuristics, read `references/planning-framework.md`.

## Inputs

Accept any combination of:
- Landing page URL, product page, business page, location page, or brand brief
- Creative assets as local files, uploaded files, existing asset IDs, or a description of planned creative
- Business goal such as awareness, reach, traffic, video views, lead generation, conversion, launch, grand opening, appointment booking, local awareness, or event promotion
- Budget, flight dates, geography, required disclaimers, audience constraints, languages, and landing URLs

If budget, dates, or market are missing, make a conservative recommendation and label the assumptions. Ask only for information that materially changes the plan.

## Workflow

1. Research the source.
   - If the user provides a URL, browse it and extract the brand, offer, products/services, locations, service area, proof points, CTA, supported claims, compliance risks, and landing URL variants.
   - If the user provides assets, inspect type, duration, dimensions, file format, messaging, CTA, target audience cues, and whether the asset is usable for AUDIO, VIDEO, or IMAGE ads.
   - If the user provides Spotify asset IDs, call `GET /ad_accounts/{id}/assets` or `GET /ad_accounts/{id}/assets/{asset_id}` to confirm asset type and status.

2. Check current Spotify Advertising guidance.
   - Browse official `ads.spotify.com` pages relevant to the format and category: policies, objectives/how-it-works, audience targeting, ad specs, and creative best practices.
   - Use official guidance to shape recommendations, and cite the pages in the final answer.
   - For restricted categories such as healthcare, finance, alcohol, gambling, politics, or medicine, add a policy note and keep targeting/copy conservative.

3. Build the campaign strategy.
   - Choose the campaign objective from API enums: `REACH`, `CLICKS`, `VIDEO_VIEWS`, `CONVERSIONS`, `LEAD_GEN`, `EVEN_IMPRESSION_DELIVERY`, `PODCAST_STREAMS`, `APP_INSTALLS`, or `WEBSITE_VISITS`.
   - For reach or local awareness, prefer one broad ad set over many narrow splits. Add a second ad set only when it controls a meaningful geo, format, budget, or message difference.
   - Put creative/message variations inside ads, not separate ad sets, unless targeting or format differs.
   - Choose asset format from available assets and the goal. Use AUDIO as the default reach format when no strong video asset exists. Add VIDEO only when video assets are available and the budget can support a separate format test.
   - Choose CTA and landing URL based on the page and asset. Use `LEARN_MORE` when conversion intent is informational or regulated.

4. Validate API targetability.
   - Fetch valid ad categories from `GET /ad_categories`; use the closest exact category code.
   - Look up every requested geo with `GET /targets/geos?country_code=<code>&q=<query>&limit=20`; never fall back to country-only without saying so.
   - Use only targeting dimensions available in the Ads API. If recommending interests, genres, artists, playlists, or languages, validate them with the matching target endpoint before presenting IDs. **Only `/targets/geos` accepts `limit`/`offset` parameters.** All other target endpoints (`/targets/genres`, `/targets/interests`, `/targets/artists`, `/targets/playlists`, `/targets/languages`) accept only `q` and/or `ids` — passing `limit` will cause a 400 error.
   - Before recommending final ad sets, run `POST /estimates/audience` for each ad set when credentials are available. This is a **top-level endpoint** (not under `/ad_accounts/`) and requires 8 fields in the request body: `ad_account_id`, `start_date`, `asset_format`, `objective`, `bid_strategy`, `bid_micro_amount`, `budget` (including `currency`), and `targets`. See `references/planning-framework.md` for the full request schema.
   - Run `POST /estimates/bid` when bid guidance is needed or the user has not supplied a bid cap. This is also a **top-level endpoint** requiring: `asset_format`, `objective`, `bid_strategy`, `currency`, and `targets`.

5. Apply execution conventions.
   - Read settings from the active platform settings file:
     - Codex: prefer `.codex/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.agents/spotify-ads-api.local.md`.
     - Claude: prefer `.claude/spotify-ads-api.local.md`, then fall back to `.codex/spotify-ads-api.local.md`, then `.agents/spotify-ads-api.local.md`.
     - Antigravity: prefer `.agents/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.codex/spotify-ads-api.local.md`.
   - Base URL: `https://api-partner.spotify.com/ads/v3`.
   - Include `Authorization: Bearer $TOKEN`, `X-Spotify-Ads-Sdk: <sdk-product>/<plugin-version>`, and `X-Spotify-Ads-Skill: campaign-strategy` on API calls.
   - Include `-w "\nHTTP_STATUS:%{http_code}"` on all API curl commands except file uploads.
   - Treat `POST /estimates/audience` and `POST /estimates/bid` as non-mutating planning calls. Do not run entity-creation POSTs in this skill unless the user explicitly asks.

## Output

Return a compact strategy package:

- **Research summary:** what the page/assets support, including substantiated claims and landing URLs.
- **Policy and creative notes:** restrictions, disclaimers, asset gaps, and Spotify best-practice implications.
- **Recommended structure:** campaign objective, ad sets, budget split, asset format, placements, frequency cap, pacing, bid strategy, CTA, and ad rotation.
- **Validated targeting:** category code, geo IDs, and any other target IDs. Mark unvalidated ideas clearly.
- **Forecasts:** audience estimate, likely-to-deliver flag, reach/impression/CPM ranges, and bid estimate when available.
- **API-ready plan:** campaign tree plus JSON skeletons for campaign and ad sets.
- **Next step:** what to confirm before handing off to `/spotify-ads-api:drafts build` (preferred) or `/spotify-ads-api:build-campaign`. Recommend the draft flow so the user can review and validate the full hierarchy before going live.

## Guardrails

- Do not target or write copy that implies knowledge of a listener's sensitive traits, diagnosis, finances, religion, politics, or protected status.
- Do not invent claims, locations, prices, certifications, or service availability not supported by the landing page or user-provided source.
- Do not over-segment reach campaigns. More ad sets are justified only by real budget control, target control, or asset-format differences.
- Do not invent API IDs. Validate them or label them as hypotheses.
- Do not retry failed POST/PATCH creation calls automatically if the user later asks to execute; check whether the resource exists first.
