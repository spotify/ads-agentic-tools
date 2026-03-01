---
name: dashboard
description: Quick performance overview of all active Spotify ad campaigns — impressions, spend, reach, clicks, and pacing at a glance.
argument-hint: "[campaign_id] | [detail]"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Campaign Dashboard

Quick performance overview with metrics, spend, and pacing for active campaigns.

## Setup

1. Read `.claude/spotify-ads-api.local.md` for `access_token`, `ad_account_id`, `environment`, `auto_execute`.
2. Base URL:
   - sandbox: `https://api-partner.spotify.com/ads-sandbox/v3`
   - production: `https://api-partner.spotify.com/ads/v3`
3. If settings file is missing, instruct the user to run `/spotify-ads-api:configure` first.

## Parsing Arguments

- No argument → Account overview (all active campaigns)
- `<campaign_id>` (UUID) → Campaign detail view for that specific campaign
- `detail` → Extended overview with ad set breakdown for all campaigns
- If ambiguous, ask the user.

---

## Account Overview (default — no argument)

Execute two API calls to build the dashboard:

### Call 1: Get campaign metrics

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=CAMPAIGN&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&fields=FREQUENCY&fields=CTR&fields=COMPLETES&\
granularity=LIFETIME&\
entity_status_type=CAMPAIGN&\
statuses=ACTIVE&\
limit=50"
```

### Call 2: Get campaign details (for names, budget, pacing)

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns?limit=50&sort_direction=DESC"
```

### Display format

```
=== Campaign Dashboard ===
Active campaigns: 3 | Total spend: $1,234.56

| Campaign         | Impressions |    Spend |  Reach | Clicks |  CTR  | Frequency |
|------------------|-------------|----------|--------|--------|-------|-----------|
| Summer Promo     |     156,234 | $450.00  | 42,100 |  1,234 | 0.79% |      1.10 |
| Q2 Brand         |      89,456 | $225.50  | 28,200 |    567 | 0.63% |      1.14 |
| Podcast Launch   |      45,000 | $112.30  | 15,800 |    289 | 0.64% |      1.02 |
```

### Formatting rules

- **Spend from `aggregate_reports`**: Already in dollars — display directly as `$X.XX` (do NOT divide by 1,000,000)
- **Budget `micro_amount` from entity details** (campaigns, ad sets): In micro-units — divide by 1,000,000 to get dollars
- **Impressions/Reach/Clicks**: Format with thousands separators (e.g., `156,234`)
- **CTR**: Display as percentage with 2 decimal places (e.g., `0.79%`)
- **Frequency**: Display with 2 decimal places
- **Filter out** rows with zero impressions for cleaner output

### Pacing calculation

When budget info is available from campaign/ad set details:

- **DAILY budgets**: Compare today's spend to daily budget. Display as: `$450 / $500 daily (90%)`
- **LIFETIME budgets**: Compare total spend to total budget and % of flight elapsed. Display as: `$2,100 / $5,000 lifetime (42%, 35% of flight elapsed)`

To calculate flight elapsed percentage:
```
elapsed_pct = (today - start_date) / (end_date - start_date) * 100
```

If pacing is significantly ahead or behind (spend % differs from elapsed % by more than 20 points), flag it:
- **Overpacing**: "Spending faster than expected — may exhaust budget early"
- **Underpacing**: "Spending slower than expected — may not fully deliver"

### Pagination

If `continuation_token` is present in the response, note that more campaigns exist and suggest running again with pagination.

---

## Campaign Detail View (`<campaign_id>`)

Drill into a specific campaign with ad set breakdown.

### Call 1: Campaign details

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns/$CAMPAIGN_ID"
```

### Call 2: Ad set metrics

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=AD_SET&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&fields=FREQUENCY&fields=COMPLETES&\
granularity=LIFETIME&\
entity_ids=$CAMPAIGN_ID&\
entity_ids_type=CAMPAIGN&\
include_parent_entity=true&\
limit=50"
```

### Call 3: Ad set details (for budget/targeting info)

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets?campaign_ids=$CAMPAIGN_ID&limit=50"
```

### Display format

```
=== Summer Promo (REACH) ===
Status: ACTIVE | Created: 2026-02-15

| Ad Set           | Format | Budget     | Impressions |   Spend |  Reach | Clicks | Completes |
|------------------|--------|------------|-------------|---------|--------|--------|-----------|
| US 18-34 Audio   | AUDIO  | $75/day    |      98,000 | $300.00 | 28,500 |    890 |    85,000 |
| US 25-54 Video   | VIDEO  | $50/day    |      58,234 | $150.00 | 13,600 |    344 |    42,000 |
```

Apply the same formatting rules as the account overview (spend from reports is already in dollars; budget micro_amount from entity details must be divided by 1,000,000).

Show targeting summary for each ad set if available (geo, age range, platforms).

---

## Extended Overview (`detail`)

Like the default account overview, but also breaks down each campaign into its ad sets.

### API calls

Use the same calls as the account overview, plus:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=AD_SET&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&fields=FREQUENCY&fields=COMPLETES&\
granularity=LIFETIME&\
include_parent_entity=true&\
entity_status_type=AD_SET&\
statuses=ACTIVE&\
limit=50"
```

And:

```bash
curl -s -H "Authorization: Bearer $TOKEN" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets?limit=50&sort_direction=DESC"
```

### Display format

Group ad sets under their parent campaign:

```
=== Campaign Dashboard (Detailed) ===
Active campaigns: 2 | Total spend: $675.50

Summer Promo (REACH) — $450.00 spent
| Ad Set           | Format | Impressions |   Spend |  Reach | Clicks |
|------------------|--------|-------------|---------|--------|--------|
| US 18-34 Audio   | AUDIO  |      98,000 | $300.00 | 28,500 |    890 |
| US 25-54 Video   | VIDEO  |      58,234 | $150.00 | 13,600 |    344 |

Q2 Brand (CLICKS) — $225.50 spent
| Ad Set           | Format | Impressions |   Spend |  Reach | Clicks |
|------------------|--------|-------------|---------|--------|--------|
| US All Audio     | AUDIO  |      89,456 | $225.50 | 28,200 |    567 |
```

---

## Execution Behavior

- If `auto_execute` is `true`, execute all API calls directly and display the dashboard.
- If `auto_execute` is `false`, present the curl commands and ask for confirmation before executing.
- On error, show the error message from the response body.
- Spend values from `aggregate_reports` are already in dollars — display directly. Budget `micro_amount` values from entity details (campaigns, ad sets) must be divided by 1,000,000. Never show raw micro-amounts to the user.
