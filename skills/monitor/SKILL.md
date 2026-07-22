---
name: monitor
description: Check Spotify Ads API campaign health — pacing, delivery issues, budget burn rate, stalled campaigns, and underpacing alerts. Use for one-shot health checks or recurring monitoring when the host supports scheduled automations.
argument-hint: "[campaign_id] | [--all]"
allowed-tools: ["Read", "Bash", "AskUserQuestion"]
---

# Spotify Ads API — Campaign Health Monitor

Diagnose delivery problems across active campaigns. Goes beyond the dashboard by running diagnostic checks and recommending specific actions.

## Setup

1. Read `access_token`, `ad_account_id`, and `auto_execute` from the active platform settings file:
   - Codex: prefer `.codex/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.agents/spotify-ads-api.local.md`.
   - Claude: prefer `.claude/spotify-ads-api.local.md`, then fall back to `.codex/spotify-ads-api.local.md`, then `.agents/spotify-ads-api.local.md`.
   - Antigravity: prefer `.agents/spotify-ads-api.local.md`, then fall back to `.claude/spotify-ads-api.local.md`, then `.codex/spotify-ads-api.local.md`.
2. Base URL: `https://api-partner.spotify.com/ads/v3`
3. If no settings file exists, instruct the user to run the configure skill first (`/spotify-ads-api:configure` on Claude/Codex, `/configure` on Antigravity).
4. Read the active platform manifest for the plugin `version`: `.codex-plugin/plugin.json` on Codex, `.claude-plugin/plugin.json` on Claude, or `plugin.json` (plugin root) on Antigravity.
5. Set `SDK_PRODUCT` to `codex-plugin` on Codex, `claude-code-plugin` on Claude, or `antigravity-cli-plugin` on Antigravity. Set `SDK_HEADER="X-Spotify-Ads-Sdk: $SDK_PRODUCT/$PLUGIN_VERSION"` and `SKILL_HEADER="X-Spotify-Ads-Skill: monitor"`. Include `-H "$SDK_HEADER"` and `-H "$SKILL_HEADER"` on all API requests.

## Parsing Arguments

- No argument or `--all` → Health check all active campaigns
- `<campaign_id>` (UUID) → Deep health check on a specific campaign (includes ad set and ad level diagnostics)
- If ambiguous, ask the user.

---

## Account-Wide Health Check (default)

### API Calls

Execute these calls to gather the data needed for diagnostics:

#### 1. Active campaigns

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns?statuses=ACTIVE&limit=50&sort_direction=DESC"
```

#### 2. Active ad sets

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets?statuses=ACTIVE&limit=50&sort_direction=DESC"
```

#### 3. Today's campaign metrics

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=CAMPAIGN&\
fields=IMPRESSIONS&fields=SPEND&fields=REACH&fields=CLICKS&fields=CTR&fields=FREQUENCY&\
granularity=DAY&\
report_start=$(date -u +%Y-%m-%dT00:00:00Z)&\
report_end=$(date -u +%Y-%m-%dT00:00:00Z)&\
entity_status_type=CAMPAIGN&\
statuses=ACTIVE&\
limit=50"
```

#### 4. Lifetime campaign metrics (for pacing)

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=CAMPAIGN&\
fields=IMPRESSIONS&fields=SPEND&fields=REACH&fields=CLICKS&\
granularity=LIFETIME&\
entity_status_type=CAMPAIGN&\
statuses=ACTIVE&\
limit=50"
```

### Health Checks

Run these diagnostics against the fetched data:

#### 1. Pacing Check

For each active campaign, compare spend progress to flight progress:

- **DAILY budgets**: Sum the daily budgets of all active ad sets under the campaign. Compare today's spend to the total daily budget.
  - Display: `$142.50 / $200.00 daily (71%)`

- **LIFETIME budgets**: Compare total lifetime spend to total lifetime budget, and compare against elapsed flight percentage.
  - `elapsed_pct = (today - start_date) / (end_date - start_date) * 100`
  - `spend_pct = total_spend / total_budget * 100`
  - Display: `$2,100 / $5,000 lifetime (42% spent, 35% of flight elapsed)`

**Alert levels:**
- **OK**: Spend % and elapsed % within 20 points of each other
- **WARNING**: 20-40 point gap between spend % and elapsed %
- **CRITICAL**: >40 point gap, OR zero spend with >24 hours elapsed since campaign start

#### 2. Stalled Delivery Check

- If an ACTIVE campaign has zero impressions today AND its start_time is more than 4 hours ago, flag as **STALLED**.
- Exclude campaigns that started within the last 4 hours (they may still be ramping up).

#### 3. Budget Exhaustion Check

For LIFETIME budgets, project when the budget will run out at the current daily burn rate:
- `daily_burn = lifetime_spend / days_elapsed`
- `days_remaining_at_pace = (budget - spend) / daily_burn`
- `projected_end = today + days_remaining_at_pace`

Flag if:
- Budget will exhaust **before** the scheduled `end_time` → "May exhaust budget early"
- Budget will be **>20% unspent** at `end_time` → "Likely to underspend"

### Display Format

```
=== Campaign Health Check ===
Checked: 3 active campaigns, 7 active ad sets
Time: 2026-05-14 14:30 UTC

| Campaign | Status | Spend Today | Pacing | Issues |
|----------|--------|-------------|--------|--------|
| Summer Promo | OK | $142.50 / $200 daily (71%) | On track | — |
| Q2 Brand | WARNING | $28.00 / $100 daily (28%) | Underpacing | 1 stalled ad set |
| Podcast Launch | CRITICAL | $0.00 / $75 daily (0%) | Stalled | No delivery today |

Issues Found (2):
  1. [WARNING] Q2 Brand: Spending at 28% of daily budget with 62% of day elapsed
     → Consider increasing bid or broadening targeting. Run: /spotify-ads-api:dashboard <campaign_id>
  2. [CRITICAL] Podcast Launch: Zero impressions today (campaign started 2026-05-12)
     → Campaign may have delivery issues. Check ad approval status with: /spotify-ads-api:monitor <campaign_id>
```

If no issues are found:

```
All 3 active campaigns are healthy. No issues detected.
```

---

## Deep Campaign Health Check (`<campaign_id>`)

### API Calls

#### 1. Campaign details

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/campaigns/$CAMPAIGN_ID"
```

#### 2. All ad sets under the campaign

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ad_sets?campaign_ids=$CAMPAIGN_ID&limit=50"
```

#### 3. All ads under the campaign

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/ads?campaign_ids=$CAMPAIGN_ID&limit=50"
```

Extract active and paused ad set IDs from Step 2 and build repeated query parameters before fetching ad set metrics:

```bash
AD_SET_IDS_QUERY="entity_ids=<AD_SET_ID_1>&entity_ids=<AD_SET_ID_2>"
```

Use the ad set IDs directly because non-`LIFETIME` aggregate reports require `entity_ids_type` to match `entity_type`. If the campaign has more than 50 ad sets, chunk report requests in groups of 50.

#### 4. Today's ad set metrics

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=AD_SET&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&fields=CTR&fields=FREQUENCY&fields=COMPLETES&\
granularity=DAY&\
report_start=$(date -u +%Y-%m-%dT00:00:00Z)&\
report_end=$(date -u +%Y-%m-%dT00:00:00Z)&\
${AD_SET_IDS_QUERY}&\
entity_ids_type=AD_SET&\
entity_status_type=AD_SET&\
limit=50"
```

#### 5. Lifetime ad set metrics

```bash
curl -s -w "\nHTTP_STATUS:%{http_code}" -H "Authorization: Bearer $TOKEN" \
  -H "$SDK_HEADER" \
  -H "$SKILL_HEADER" \
  "$BASE_URL/ad_accounts/$AD_ACCOUNT_ID/aggregate_reports?\
entity_type=AD_SET&\
fields=IMPRESSIONS&fields=SPEND&fields=CLICKS&fields=REACH&fields=FREQUENCY&\
granularity=LIFETIME&\
${AD_SET_IDS_QUERY}&\
entity_ids_type=AD_SET&\
entity_status_type=AD_SET&\
include_parent_entity=true&\
limit=50"
```

### Additional Health Checks (Deep Mode)

In addition to the pacing, stalled, and exhaustion checks from the account-wide mode, the deep check adds:

#### 4. Ad Health Check

- **Rejected ads**: Ads with status `REJECTED` — flag with recommendation to review and re-create.
- **Pending ads**: Ads with status `PENDING` where `created_at` is more than 24 hours ago — flag as unusually slow approval.
- **Delivery OFF**: Ads with `delivery: OFF` under an ACTIVE ad set — flag as potentially unintentional.

#### 5. Audience Fatigue Check

- **High frequency**: If lifetime frequency > 3.0 on any ad set, warn about potential audience fatigue. Suggest expanding targeting or adding new creative.
- **Low CTR**: If CTR < 0.1% with > 10,000 impressions on any ad set, suggest reviewing creative or targeting.

### Display Format

```
=== Summer Promo — Deep Health Check ===
Campaign: ACTIVE | Objective: REACH | Created: 2026-04-01

Ad Set Health:
| Ad Set | Format | Budget | Spend Today | Pacing | Freq | Issues |
|--------|--------|--------|-------------|--------|------|--------|
| US 18-34 Audio | AUDIO | $75/day | $68.50 (91%) | OK | 1.8 | — |
| US 25-54 Video | VIDEO | $50/day | $12.00 (24%) | WARNING | 0.4 | Underpacing |

Ad Health:
| Ad | Ad Set | Status | Delivery | Issues |
|----|--------|--------|----------|--------|
| 30s Spot A | US 18-34 Audio | APPROVED | ON | — |
| 30s Spot B | US 18-34 Audio | REJECTED | — | Rejected |
| 15s Video | US 25-54 Video | PENDING | ON | Pending >24h |

Recommendations:
  1. "US 25-54 Video" is underpacing at 24% spend. Consider:
     - Broadening targeting (current: US, ages 25-54, VIDEO)
     - Increasing bid cap
     - Run: /spotify-ads-api:ads ad-sets get <ad_set_id>
  2. "30s Spot B" was rejected. Review and re-create via /spotify-ads-api:ads ads create
  3. "15s Video" has been pending approval for >24h — check if creative meets format requirements.
```

---

## Recurring Monitoring

After displaying results, suggest recurring checks only when the host environment supports scheduled tasks or automations:

```
To monitor automatically, schedule a recurring run of:
  /spotify-ads-api:monitor --all
```

---

## Execution Behavior

- If `auto_execute` is `true`, execute all API calls directly and display the health check.
- If `auto_execute` is `false`, present the curl commands and ask for confirmation before executing.
- Always check the `HTTP_STATUS:` line from curl output to determine success or failure before interpreting the response body.
- On error, show the error message from the response body and continue with available data.

## Formatting Rules

- **Spend from `aggregate_reports`**: Already in dollars — display directly as `$X.XX`.
- **Budget `micro_amount` from entity details**: In micro-units — divide by 1,000,000 to get dollars.
- **Impressions/Reach/Clicks**: Format with thousands separators (e.g., `156,234`).
- **CTR**: Display as percentage with 2 decimal places (e.g., `0.79%`).
- **Frequency**: Display with 1 decimal place.
- **Percentages**: Round to nearest integer for pacing (e.g., `71%`).
