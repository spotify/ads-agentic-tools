# Test Harness

Structured test scenarios for validating the Spotify Ads API plugin.

## Prerequisites

1. A Spotify Developer app with OAuth credentials (client ID and secret)
2. A Spotify Ads ad account
3. Python 3.8+ (for OAuth script tests)
4. Claude Code CLI with the plugin installed

## Running Tests

### Setup

1. Install the plugin:
   ```bash
   claude plugin add spotify-ads-api
   ```

2. Configure credentials:
   ```
   /spotify-ads-api:configure
   ```

### Execution Order

Scenarios should be run sequentially, as some depend on entities created in prior steps:

| Order | Scenario | Depends On |
|-------|----------|------------|
| 1 | Configure OAuth | — |
| 2 | List campaigns | Scenario 1 (configured credentials) |
| 3 | Create campaign | Scenario 1 |
| 4 | Create ad set | Scenario 3 (campaign ID) |
| 5 | Create audio ad | Scenario 4 (ad set ID) + uploaded assets |
| 6 | Full build-campaign | Scenario 1 + uploaded assets |
| 7 | Aggregate report | Scenario 1 + existing campaigns |
| 8 | Pause campaign | Scenario 3 or 6 (campaign to pause) |
| 9 | Async CSV report | Scenario 1 + existing campaigns |
| 10 | Token refresh | Scenario 1 (OAuth credentials) |

### Validation Checklist

For each scenario, verify:

- [ ] Curl command matches expected format in `test-scenarios.md`
- [ ] API-specific quirks are handled correctly (see each scenario's "Quirks tested")
- [ ] API response is 2xx
- [ ] Output is formatted readably (tables, masked tokens)
- [ ] No internal endpoints or credentials leaked in output

### Notes

- Token refresh requires valid OAuth credentials configured on the Spotify app
