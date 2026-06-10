# Spotify Ads Agentic Tools

A Codex, Claude Code, and Gemini CLI plugin package that lets you manage Spotify advertising campaigns through natural language. Create campaigns, target audiences, launch ads, and pull performance reports — all by describing what you want in plain English.

Check out our post on the [Spotify Engineering Blog](https://engineering.atspotify.com/2026/5/spotify-ads-api-claude-plugins).

## Prerequisites

- Codex, [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code), or [Gemini CLI](https://geminicli.com/)
- A [Spotify Developer](https://developer.spotify.com/) account with an ads-enabled app
- A Spotify Ads ad account ID
- Python 3.8+ (for automated OAuth flow; optional — manual flow available as fallback)

## Install

### Claude Code

```bash
claude plugin i spotify-ads-api
```

### Codex

Add the Spotify Ads API plugin marketplace:

```bash
codex plugin marketplace add spotify/ads-agentic-tools
```

Restart Codex after adding the marketplace. Then open the plugin directory in the Codex app, or run `codex` and enter `/plugins` in the CLI. Select the added marketplace and install/enable **Spotify Ads API**.

Use `codex plugin marketplace upgrade` later to refresh installed marketplace sources.

### Gemini CLI

```bash
gemini extensions install https://github.com/spotify/ads-agentic-tools
```

Restart Gemini CLI, then verify with `/extensions`. On Gemini, skills activate automatically from natural language (or browse them with `/skills list`); run `/configure` for first-time setup instead of `/spotify-ads-api:configure`. Note: automatic OAuth token refresh uses the macOS Keychain, so auto-refresh is macOS-only.

## Install from source

Use a source checkout for local development or testing unreleased changes.

1. Clone the repository:
   ```bash
   git clone https://github.com/spotify/ads-agentic-tools.git
   cd ads-agentic-tools
   ```

2. For Codex, register the checkout as a local marketplace:
   ```bash
   codex plugin marketplace add "$(pwd)"
   ```

   Restart Codex after adding the marketplace. Then open the plugin directory in the Codex app, or run `codex` and enter `/plugins` in the CLI. Select the local marketplace and install/enable **Spotify Ads API**.

3. For Claude Code, launch with the plugin directory:
   ```bash
   claude --plugin-dir "$(pwd)"
   ```

   The Claude `--plugin-dir` flag loads the plugin for that session only. You can also add it to a shell alias if you use it frequently:
   ```bash
   alias claude-ads='claude --plugin-dir /path/to/ads-agentic-tools'
   ```

4. For Gemini CLI, link the checkout as a local extension:
   ```bash
   gemini extensions link "$(pwd)"
   ```

   The link is a symlink, so source changes are picked up on the next Gemini CLI restart.

The repository includes platform-specific marketplace metadata: `.agents/plugins/marketplace.json` for Codex and `.claude-plugin/marketplace.json` for Claude Code. Gemini CLI has no marketplace file — it installs directly from the repository using the root `gemini-extension.json` manifest. Keep all three manifests in sync when changing plugin metadata.

## Configure

1. **Set up the redirect URI in Spotify Developer Dashboard:**
   - Go to [developer.spotify.com](https://developer.spotify.com/) and open your app settings
   - Under **Redirect URIs**, add: `http://127.0.0.1:8080/callback`
   - Save the changes
   - Open [https://adsmanager.spotify.com/api-terms](https://adsmanager.spotify.com/api-terms) and make sure the ad account you want to use is selected. Accept the terms to authorize your client id to access your ad account through Ads API.

2. Configure OAuth credentials:
   ```
   /spotify-ads-api:configure
   ```
   (On Gemini CLI, run `/configure` instead — the skill names below all apply, but the slash-command prefix is Claude Code/Codex syntax.)
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

Skill names below use Claude Code/Codex slash-command syntax. On Gemini CLI, the same skills activate automatically from natural language (browse them with `/skills list`), and setup is `/configure`.

| Skill | Description |
|-------|-------------|
| `/spotify-ads-api:configure` | Set up OAuth credentials, ad account, and preferences |
| `/spotify-ads-api:campaigns` | List, create, get, or update campaigns |
| `/spotify-ads-api:ads` | Manage ad sets and ads (list, create, get, update) |
| `/spotify-ads-api:campaign-strategy` | Plan API-ready campaign structure and targeting from a landing page, business brief, or creative assets |
| `/spotify-ads-api:build-campaign` | Create a full campaign hierarchy from a plain-text description |
| `/spotify-ads-api:report` | Pull aggregate metrics, audience insights, or async CSV reports |
| `/spotify-ads-api:assets` | Upload, list, and manage creative assets |
| `/spotify-ads-api:dashboard` | Quick performance overview of active campaigns |
| `/spotify-ads-api:monitor` | Diagnose pacing, delivery, stalled campaigns, and underdelivery issues |
| `/spotify-ads-api:export` | Export campaign hierarchy, targeting, budget, and optional metrics to CSV |
| `/spotify-ads-api:bulk` | Apply batch pause, resume, budget, delivery, archive, and creative-swap workflows |
| `/spotify-ads-api:clone` | Clone campaigns or ad sets with optional date, budget, name, or targeting changes |

## Natural Language Examples

The plugin includes an agent that interprets natural language requests automatically:

- "Create a campaign called Summer Sale with a reach objective"
- "Set up an audio ad targeting 18-34 year olds in the US with $50/day budget"
- "Show me impressions, spend, and clicks for all campaigns last month"
- "Pause the Summer Sale campaign"
- "Generate a CSV report of daily spend by campaign for January"
- "Build me a complete audio campaign targeting US listeners aged 25-44"
- "Plan the best Spotify campaign structure for this product page"
- "Use these creative assets to recommend targeting and ad sets"
- "Clone last quarter's campaign and move the dates to next month"
- "Export all campaigns with metrics for the last 30 days"
- "Check which active campaigns are underpacing"
- "Pause all active ad sets in the Summer Sale campaign"
- "Upload my-audio.mp3 as a creative asset"
- "How are my campaigns performing?"

## Configuration Reference

Settings are stored in `.codex/spotify-ads-api.local.md` on Codex, `.claude/spotify-ads-api.local.md` on Claude, and `.gemini/spotify-ads-api.local.md` on Gemini. Each platform falls back to the other settings files if its preferred file does not exist. All three paths are gitignored.

| Field | Description | Default |
|-------|-------------|---------|
| `access_token` | OAuth2 bearer token | — |
| `refresh_token` | Token for automatic renewal | — |
| `token_expires_at` | ISO 8601 expiry timestamp | — |
| `client_id` | Spotify app client ID | — |
| `ad_account_id` | Default ad account UUID | — |
| `auto_execute` | Skip confirmation prompts | `false` |

The client secret is stored in the **macOS Keychain** (not in the settings file) for security. It is saved during `/spotify-ads-api:configure` and retrieved automatically by the token refresh hook.

## Troubleshooting

**"Token may be invalid or expired"**
If using OAuth, the plugin auto-refreshes tokens. If the refresh token is also expired, re-run `/spotify-ads-api:configure`. If using direct token mode, obtain a new token and run `/spotify-ads-api:configure token <new-token>`.

**"Ad account ID may be incorrect"**
Verify your ad account UUID. You can find it in the Spotify Ads Manager or by asking the plugin to list accounts after configuring a valid token.

**"Settings file not found"**
Run `/spotify-ads-api:configure` to create the settings file.

**"Min audience threshold was not met"**
Your targeting is too narrow for the selected ad format. Try broadening the age range, adding more platforms, or switching from VIDEO to AUDIO format.

**"Asset stuck in PROCESSING"**
Large files may take longer to transcode. Check status with `/spotify-ads-api:assets get <id>`. If status is REJECTED, the file may not meet format requirements.

**Skill not activating on Gemini CLI**
Run `/skills list` to confirm the extension's skills loaded, and `/extensions` to confirm the extension is enabled. Restart Gemini CLI after installing or linking.

## License

Copyright 2026 Spotify, Inc.

Licensed under the Apache License, Version 2.0: https://www.apache.org/licenses/LICENSE-2.0

## Security Issues?

Please report sensitive security issues via Spotify's bug-bounty program (https://hackerone.com/spotify) rather than GitHub.
