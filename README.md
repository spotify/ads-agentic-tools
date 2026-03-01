# spotify-ads-api

A Claude Code plugin that lets you manage Spotify advertising campaigns through natural language. Create campaigns, target audiences, launch ads, and pull performance reports — all by describing what you want in plain English.

## Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- A [Spotify Developer](https://developer.spotify.com/) account with an ads-enabled app
- A Spotify Ads ad account ID
- Python 3.8+ (for automated OAuth flow; optional — manual flow available as fallback)

## Quick Start

1. Install the plugin:
   ```bash
   claude plugin add spotify-ads-api
   ```

2. Configure OAuth credentials:
   ```
   /spotify-ads-api:configure
   ```
   This opens your browser for Spotify authorization, then saves your tokens locally with automatic refresh.

3. Create your first campaign:
   ```
   /spotify-ads-api:build-campaign Create an audio campaign called Summer Promo targeting US listeners aged 25-44 with $100/day budget
   ```

## Authentication

The plugin supports three authentication modes:

### OAuth 2.0 (Recommended)
Run `/spotify-ads-api:configure` or `/spotify-ads-api:configure oauth`. This launches an automated OAuth flow using a local Python script. Your tokens are stored locally and refresh automatically before API calls.

### Manual OAuth
Run `/spotify-ads-api:configure manual` if Python is not available. You'll manually open the authorization URL, copy the redirect, and the plugin exchanges the code for tokens via curl.

### Direct Token (Legacy)
Run `/spotify-ads-api:configure token <your-token>`. Accepts a pre-obtained access token. No automatic refresh — token expires in ~1 hour.

## Available Skills

| Skill | Description |
|-------|-------------|
| `/spotify-ads-api:configure` | Set up OAuth credentials, ad account, and preferences |
| `/spotify-ads-api:campaigns` | List, create, get, or update campaigns |
| `/spotify-ads-api:ads` | Manage ad sets and ads (list, create, get, update) |
| `/spotify-ads-api:build-campaign` | Create a full campaign hierarchy from a plain-text description |
| `/spotify-ads-api:report` | Pull aggregate metrics, audience insights, or async CSV reports |

## Natural Language Examples

The plugin includes an agent that interprets natural language requests automatically:

- "Create a campaign called Summer Sale with a reach objective"
- "Set up an audio ad targeting 18-34 year olds in the US with $50/day budget"
- "Show me impressions, spend, and clicks for all campaigns last month"
- "Pause the Summer Sale campaign"
- "Generate a CSV report of daily spend by campaign for January"
- "Build me a complete audio campaign targeting US listeners aged 25-44"

## Configuration Reference

Settings are stored in `.claude/spotify-ads-api.local.md` (gitignored):

| Field | Description | Default |
|-------|-------------|---------|
| `access_token` | OAuth2 bearer token | — |
| `refresh_token` | Token for automatic renewal | — |
| `token_expires_at` | ISO 8601 expiry timestamp | — |
| `client_id` | Spotify app client ID | — |
| `client_secret` | Spotify app client secret | — |
| `ad_account_id` | Default ad account UUID | — |
| `environment` | `sandbox` or `production` | `sandbox` |
| `auto_execute` | Skip confirmation prompts | `false` |

## Sandbox vs Production

By default, the plugin uses the **sandbox** environment (`ads-sandbox/v3`). Sandbox lets you test API calls without spending real budget. To switch to production, run `/spotify-ads-api:configure` and select `production`, or edit the `environment` field in `.claude/spotify-ads-api.local.md`.

Sandbox limitations:
- No real ad delivery
- Limited reporting data
- Some features may behave differently

## Troubleshooting

**"Token may be invalid or expired"**
If using OAuth, the plugin auto-refreshes tokens. If the refresh token is also expired, re-run `/spotify-ads-api:configure`. If using direct token mode, obtain a new token and run `/spotify-ads-api:configure token <new-token>`.

**"Ad account ID may be incorrect"**
Verify your ad account UUID. You can find it in the Spotify Ads Manager or by asking the plugin to list accounts after configuring a valid token.

**"Settings file not found"**
Run `/spotify-ads-api:configure` to create the settings file.

**"Min audience threshold was not met"**
Your targeting is too narrow for the selected ad format. Try broadening the age range, adding more platforms, or switching from VIDEO to AUDIO format.

**Sandbox returns unexpected errors**
Some API behaviors differ between sandbox and production. If a call works in production but not sandbox, this may be a sandbox limitation.

## License

MIT
