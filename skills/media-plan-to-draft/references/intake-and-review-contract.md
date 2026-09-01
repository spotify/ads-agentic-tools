# Media Plan Intake and Review Contract

Use this contract to preserve source intent while converting heterogeneous plans into a reviewable Spotify Ads hierarchy. Keep the ledger in memory or in the Markdown implementation plan; a separate machine-readable artifact is optional.

## Completeness States

| State | Meaning |
|---|---|
| `CONFIRMED` | Explicitly supplied by the user or unambiguously present in the source plan |
| `VALIDATED` | Confirmed against the selected ad account or a live Ads API response |
| `INFERRED` | Recommended from context or an existing planning default; user has not yet confirmed it |
| `PLACEHOLDER` | A valid temporary value the user has allowed, such as provisional copy or URL |
| `DEFERRED` | Intentionally omitted until a future step, such as an audience or creative not yet uploaded |
| `BLOCKED` | Unsafe to create because scope, destination, or a material choice is unresolved or incompatible |

One value can carry source provenance and later become `VALIDATED`; keep both the origin and the current state.

## Canonical Ledger

Capture fields only when relevant. Preserve the source label beside the normalized value when terminology differs.

### Plan and source

- Source file(s), version/date, worksheet/page/table, advertiser, brand, market, currency, time zone, and stated total.
- Source line identifier, channel/publisher, buying method, product or package, planned KPI, notes, and provenance.
- Whether a line is Spotify-executable, manual/reserved, informational, non-Spotify, or excluded.

### Proposed campaign

- Name, destination ad account, ad product or buying channel, objective or delivery-goal group, purchase order, and grouping rationale.

### Proposed ad set

- Name, parent campaign, start/end, budget amount and type, asset format, category, bid strategy/range, pacing, frequency caps, delivery goal, placements, platform, and promotion fields.
- Targets as source labels plus exact API keys and resolved IDs: geo, age, gender, language, genre, interest, artist, playlist, custom audience, lookalike, and exclusions when supported.
- Forecast input, output, timestamp, scenario label, and any omitted target.

### Proposed ad

- Name, parent ad set, format, advertiser, tagline/copy, CTA, clickthrough URL, asset IDs and names, carousel ordering, tracking, schedule override, delivery, and weight.

## Normalization Rules

1. Never assume one spreadsheet row equals one ad set. A row may be a subtotal, package, creative variant, reserved placement, audience slice, or reporting note.
2. Preserve rows that share delivery settings as candidate ads; split ad sets only for a material execution or measurement boundary.
3. Keep Auction and reserved/managed-service buying lines separate unless the live product catalog and source explicitly support one hierarchy.
4. Preserve source budget semantics. Do not convert lifetime to daily, net to gross, or media to production without a displayed calculation and approval.
5. Use the user's time zone for review and normalize API timestamps only after the time zone is known. Flag past dates or inverted flights.
6. Treat ranges as ranges. Do not silently choose the midpoint of a bid, budget, age, or flight range.
7. Exact IDs are authoritative only after account lookup. Names and patterns are candidate selectors, not IDs.
8. A missing audience or asset is not evidence that the source intended broad targeting or a different creative.
9. If multiple source values conflict, show both with provenance and mark the normalized field `BLOCKED` unless one is clearly a subtotal, superseded version, or explanatory note.
10. Record arithmetic reconciliation independently from API validation; both can pass or fail separately.

## Review Gate Template

Before asking for approval, show:

```text
Destination: <account name and ID> (<currency>)
Draft scope: <campaign count> campaigns / <ad set count> ad sets / <ad count> ads
Excluded/manual: <count and short reason>
Incomplete: <deferred or placeholder fields and expected validation impact>
Forecast basis: <targeting, formats, bid scenarios, omitted audiences>
Material assumptions: <inferred choices>
Open questions: <blocked choices>
```

Approval must be unambiguous about this displayed scope. Examples that qualify include “Create this exact draft” or “Proceed with the draft and leave the two named audiences deferred.” A vague “looks interesting” does not qualify.

If the user accepts an incomplete draft, convert the accepted items from unresolved questions into documented `DEFERRED` or `PLACEHOLDER` entries. Keep genuine scope or compatibility conflicts `BLOCKED`.
