---
name: build-campaign
description: Create a complete Spotify ad campaign from a plain-language brief using a fast draft, validate, and publish workflow.
argument-hint: "<plain-text campaign description>"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Campaign Builder

Turn a campaign brief into a reviewed JSON plan, then delegate deterministic API work to `scripts/campaign-flow.py`. Do not route this operation through the drafts skill and do not issue individual create requests yourself.

## Interaction Contract

Use at most three user pauses:

1. Ask one consolidated question for all required details that cannot be inferred.
2. Present the complete plan and ask once for approval to create and validate drafts.
3. After successful validation, ask separately whether to publish. Publishing always requires explicit confirmation immediately before execution, even when `auto_execute` is true.

Do not ask for values that can be safely defaulted. Do not show or seek approval for each underlying API request.

## Defaults and Required Decisions

Apply these defaults unless the brief says otherwise:

- Campaign objective: `REACH`
- Budget type: `DAILY`
- Asset format: `AUDIO`
- Bid strategy: `MAX_BID`; default bid is `15000000` micro-units
- Pacing: `PACING_EVEN`
- Platforms: `ANDROID`, `DESKTOP`, `IOS`
- Placements: `MUSIC`
- Ages: 18–54
- Delivery: `ON`

The user or lookup results must supply:

- Campaign and ad-set names
- Start time; end time for `LIFETIME` budgets
- Positive budget
- Valid ad category
- Exact geo IDs when a location narrower than a country is requested
- For every ad: name, tagline, advertiser name, creative asset, logo asset, companion asset for audio, CTA key, and clickthrough URL

Convert dollars to micro-units by multiplying by 1,000,000. Use ISO 8601 UTC timestamps.

## Phase 1: Prepare in One Tool Call

Read settings only to verify that configuration exists. Never display tokens.

Run the preparation command once. It fetches categories and assets concurrently. Include one `geo_queries` entry for each user-specified region, DMA, city, or postal code. Omit country-only targets.

```bash
SPOTIFY_ADS_API_BASE="https://api-partner.spotify.com/ads/v3" \
python3 "$PLUGIN_ROOT/skills/build-campaign/scripts/campaign-flow.py" prepare <<'JSON'
{"geo_queries":[{"country_code":"US","q":"Connecticut"}]}
JSON
```

Set `PLUGIN_ROOT` from `CODEX_PLUGIN_ROOT`, `CLAUDE_PLUGIN_ROOT`, or the installed plugin root. On Antigravity, derive it as two directories above this skill.

Use the results to resolve category, assets, and geo targeting. If a lookup is ambiguous, include it in the single consolidated question rather than creating another question per field.

## Phase 2: Build the Reviewed Plan

Create one JSON object using this shape:

```json
{
  "campaign": {
    "name": "Summer Sale",
    "objective": "REACH"
  },
  "ad_sets": [
    {
      "name": "US Audio",
      "start_time": "2026-08-01T12:00:00Z",
      "budget": {"micro_amount": 50000000, "type": "DAILY"},
      "asset_format": "AUDIO",
      "category": "ADV_X_Y",
      "bid_strategy": "MAX_BID",
      "bid_micro_amount": 15000000,
      "pacing": "PACING_EVEN",
      "delivery": "ON",
      "targets": {
        "age_ranges": [{"min": 18, "max": 54}],
        "geo_targets": {"country_code": "US"},
        "platforms": ["ANDROID", "DESKTOP", "IOS"],
        "placements": ["MUSIC"]
      },
      "ads": [
        {
          "name": "Summer Audio",
          "tagline": "Save this summer",
          "advertiser_name": "Example Brand",
          "assets": {
            "asset_id": "uuid",
            "logo_asset_id": "uuid",
            "companion_asset_id": "uuid"
          },
          "call_to_action": {
            "key": "SHOP_NOW",
            "clickthrough_url": "https://example.com"
          },
          "delivery": "ON"
        }
      ]
    }
  ]
}
```

Before execution, show a compact hierarchy plus budget, schedule, targeting, bid, and chosen assets. Ask once: create these drafts and validate them?

After approval, pass the JSON on stdin in one Bash invocation:

```bash
SPOTIFY_ADS_API_BASE="https://api-partner.spotify.com/ads/v3" \
python3 "$PLUGIN_ROOT/skills/build-campaign/scripts/campaign-flow.py" build <<'JSON'
<reviewed plan JSON>
JSON
```

The runner performs local schema guardrails, audience estimates concurrently, creates the dependent draft hierarchy sequentially, fetches the current hierarchy version, and validates once. It never retries POST requests. If it reports `partial_draft`, explain exactly which drafts were created and stop.

If an audience estimate fails, no drafts are created. Present the API message and ask for one targeting adjustment. If hierarchy validation returns errors, present them by entity and suggest a single consolidated correction.

## Phase 3: Publish

After a successful build, show the created draft IDs, audience-estimate summary, and validation result. Ask whether to publish now or keep the hierarchy as a draft.

Only after explicit publish confirmation, run:

```bash
SPOTIFY_ADS_API_BASE="https://api-partner.spotify.com/ads/v3" \
python3 "$PLUGIN_ROOT/skills/build-campaign/scripts/campaign-flow.py" publish \
  --draft-campaign-id "<uuid>" --confirm-publish PUBLISH
```

The runner fetches the current version, validates, checks the version again, revalidates only if it changed, then publishes. Never pass `--confirm-publish PUBLISH` before the user confirms.

## Non-negotiable Schema Rules

- `bid_strategy` is a string: `MAX_BID`, `COST_PER_RESULT`, `AUTOBID`, or `UNSET`.
- `geo_targets` is one flat object containing `country_code` and optional ID arrays.
- Platforms are only `ANDROID`, `DESKTOP`, and `IOS`.
- `category` is required on every ad set.
- `end_time` is required for `LIFETIME` budgets.
- Audio ads require `companion_asset_id`.
- CTA fields are `key` and `clickthrough_url`.
- Never replace a requested region, DMA, city, or postal code with country-only targeting.
- Never retry a failed create or publish request automatically.

For direct live creation, only when explicitly requested, use the campaigns and ads skills instead of this workflow and explain that partial live hierarchies are possible.
