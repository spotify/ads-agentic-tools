# Campaign Strategy Planning Framework

Use this reference after `campaign-strategy` triggers. Keep the plan tied to the landing page, available assets, Spotify Advertising guidance, and Ads API validation.

## Campaign Objective Selection

| User goal | API objective | Default structure |
| --- | --- | --- |
| Awareness, launch, store/location awareness, broad message recall | `REACH` | Broad geo, broad age, audio-first, limited ad set splits. MAX_BID only. |
| Website traffic, learn more, product detail page visits | `CLICKS` | One or two intent-aligned ad sets, clear CTA, landing-page consistency. MAX_BID or COST_PER_RESULT. |
| Video asset distribution, trailer, product demo, visual storytelling | `VIDEO_VIEWS` | Video ad set if asset exists and audience is broad enough. VIDEO only, no DESKTOP. MUSIC placement only. MAX_BID only. |
| Lead form or high-intent inquiry | `LEAD_GEN` | Use only if the account and destination flow support lead capture. AUDIO format. MAX_BID only. |
| Conversion-optimized traffic | `CONVERSIONS` | Use only when conversion setup, measurement, and event destination are known |
| Even delivery guarantee is more important than reach optimization | `EVEN_IMPRESSION_DELIVERY` | Use only when the user asks for even impression delivery. MAX_BID only. |
| Podcast listener growth, podcast streams | `PODCAST_STREAMS` | AUDIO format, PODCAST placement. MAX_BID only. |
| Mobile app installs | `APP_INSTALLS` | IOS or ANDROID only (not both, no DESKTOP). Requires mobile_app_id on ad set. MAX_BID only. |
| Website visits, drive traffic | `WEBSITE_VISITS` | AUDIO and VIDEO formats. MAX_BID only. |

For reach, avoid splitting by every product feature or service line. Use multiple ads inside one ad set to test messages while keeping delivery scale.

## Targeting Heuristics

Start with the broadest targeting that is still commercially relevant, then narrow only when the business case is clear.

- **Local businesses and locations:** map the service area from the page. Validate city, ZIP, region, and DMA IDs through `/targets/geos`. For small towns, test both a core catchment and the broader DMA with `/estimates/audience`; recommend the broader one if the narrow catchment is too small.
- **Regional or national products:** use region or country geos only when the page supports that availability. Do not assume nationwide service from a local page.
- **Age:** default to broad adult ranges for reach. Narrow age only for legal requirements, product fit, or explicit user direction.
- **Gender:** avoid unless the product has a strong non-sensitive reason and policy allows it.
- **Platforms:** default to all valid values: `ANDROID`, `DESKTOP`, `IOS`.
- **Placements:** default to `MUSIC` for reach. Add `PODCAST` when brand safety and creative fit are acceptable; use sensitive topic exclusions when needed.
- **Behavioral/contextual targeting:** validate available IDs before using them. Prefer light contextual alignment over narrow behavioral targeting for reach campaigns.

Relevant target endpoints:
- `GET /targets/geos` — supports `country_code` (required), `q`, `ids`, `limit`, `offset`
- `GET /targets/interests` — supports `q` and `ids` only. Returns `interests_with_subtargets` array (the `interests` key is always null). Both parent IDs and subtarget IDs are valid for `interest_ids`.
- `GET /targets/genres` — supports `q` and `ids` only. Returns `genres` array.
- `GET /targets/artists` — supports `q` and `artist_ids` only
- `GET /targets/playlists` — supports `q` only
- `GET /targets/languages` — no documented parameters

**Only `/targets/geos` accepts `limit` and `offset`.** All other target endpoints reject pagination parameters with a 400 error. They return the full list in one response.

## Structure Rules

Separate ad sets only when one of these differs:
- Objective or delivery goal
- Geo market that needs budget control
- Format (`AUDIO`, `VIDEO`, `IMAGE`)
- Budget or flight dates
- Audience strategy that should be forecast and measured independently
- Regulated or policy-sensitive targeting requirement

Prefer ad rotation when only the message differs:
- Feature/service message
- CTA wording
- Brand proof point
- Creative tone
- Landing page variant for the same audience

## Budgets, Bidding, and Forecasting

- Convert dollars to micro-amounts for budgets and bids.
- Use `MAX_BID` with `bid_micro_amount` unless the user requests automated bidding. Use `AUTOBID` when the user wants automatic bid optimization (no `bid_micro_amount` required). Use `COST_PER_RESULT` only with the CLICKS objective.
- Run `POST /estimates/bid` when recommending a bid cap.
- Run `POST /estimates/audience` for every recommended ad set before presenting the final executable structure when credentials are available.
- For reach, use `PACING_EVEN` and a frequency cap such as 2 impressions per user per week unless the user needs urgency.
- If the forecast says the ad set is too small or unlikely to deliver, broaden in this order: geo, age, platforms, placements, then remove optional interest/genre filters.

**Estimate endpoints are top-level** — use `POST /estimates/audience` and `POST /estimates/bid`, NOT `/ad_accounts/{id}/estimates/...`. The `ad_account_id` goes in the request body.

`POST /estimates/audience` required body:
```json
{
  "ad_account_id": "<from settings>",
  "start_date": "2026-01-15T00:00:00Z",
  "end_date": "2026-02-15T23:59:59Z",
  "asset_format": "AUDIO",
  "objective": "REACH",
  "bid_strategy": "MAX_BID",
  "bid_micro_amount": 15000000,
  "budget": {
    "micro_amount": 5000000,
    "type": "DAILY",
    "currency": "USD"
  },
  "frequency_caps": [
    { "frequency_unit": "WEEK", "frequency_period": 1, "max_impressions": 2 }
  ],
  "targets": { "...same Targets as ad set..." }
}
```

All 8 fields (`ad_account_id`, `start_date`, `asset_format`, `objective`, `bid_strategy`, `bid_micro_amount`, `budget`, `targets`) are required. The `budget` object requires `currency` (e.g. "USD") in addition to `micro_amount` and `type`.

`POST /estimates/bid` required body:
```json
{
  "asset_format": "AUDIO",
  "objective": "REACH",
  "bid_strategy": "MAX_BID",
  "currency": "USD",
  "targets": { "...same Targets as ad set..." }
}
```

All 5 fields (`asset_format`, `objective`, `bid_strategy`, `currency`, `targets`) are required.

## Creative and Asset Guidance

Use current official Spotify Advertising guidance from `ads.spotify.com` for final recommendations. As of current guidance:
- Audio ads should stay focused on one or two key ideas.
- For a 30-second script, keep copy tight; use the current audio specs as the stricter limit if they differ from creative best-practice guidance.
- Mention the brand in the first five seconds.
- Use a clear CTA and one HTTPS clickthrough URL.
- Audio ads need an audio asset plus visual companion/logo assets in the Ads API flow; `companion_asset_id` is required for AUDIO ads.
- Tagline max is 40 characters; advertiser name max is 25 characters.
- Companion and logo images should be square and at least 600x600 where applicable.
- Consider audio plus video only when assets and budget support a meaningful format split.

When assets are provided:
- Classify each as `AUDIO`, `VIDEO`, or `IMAGE`.
- Check whether it matches the ad set format and API asset requirements.
- Extract message, brand mention timing, CTA, claims, and landing-page fit.
- Recommend edits if the asset is too long, unfocused, missing the brand early, missing a CTA, or unsupported by the landing page.

## Restricted and Sensitive Categories

Use conservative planning for restricted categories. Spotify policy may restrict healthcare, finance, gambling, alcohol, political, medicine/pharma, and other categories by advertiser, product, region, or creative content.

For sensitive categories:
- Prefer broad contextual/demographic targeting over targeting that could imply a sensitive condition or trait.
- Avoid copy such as "struggling with...", "diagnosed with...", or "people like you with..." unless approved by legal and policy.
- Include required disclaimers or emergency language when the landing page or category requires it.
- Cite the official Spotify Advertising policies page in the final answer.

## API-Ready Output Template

```text
Campaign: <name> (objective: <OBJECTIVE>)
|-- Ad Set 1: <name> (<asset_format>, <budget>, <geo>, <age>, <placements>)
|   |-- Ad 1: <message angle> -> <CTA> -> <landing URL>
|   `-- Ad 2: <message angle> -> <CTA> -> <landing URL>
`-- Ad Set 2: <only if justified>
```

For each ad set, include:

```json
{
  "name": "<ad set name>",
  "budget": {"micro_amount": 100000000, "type": "DAILY"},
  "asset_format": "AUDIO",
  "category": "ADV_X_Y",
  "targets": {
    "age_ranges": [{"min": 18, "max": 99}],
    "geo_targets": {"country_code": "US", "dma_ids": ["..."]},
    "platforms": ["ANDROID", "DESKTOP", "IOS"],
    "placements": ["MUSIC"]
  },
  "bid_strategy": "MAX_BID",
  "bid_micro_amount": 15000000,
  "pacing": "PACING_EVEN",
  "frequency_caps": [
    {"frequency_unit": "WEEK", "frequency_period": 1, "max_impressions": 2}
  ]
}
```
