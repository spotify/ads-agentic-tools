# Spotify Ads Agentic Tools

A Codex, Claude Code, and Antigravity CLI plugin package that lets you manage Spotify advertising campaigns through natural language. Create campaigns, target audiences, launch ads, and pull performance reports — all by describing what you want in plain English.

Check out our post on the [Spotify Engineering Blog](https://engineering.atspotify.com/2026/5/spotify-ads-api-claude-plugins).

## Prerequisites

- Codex, [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code), or [Antigravity CLI](https://antigravity.google/)
- A [Spotify Developer](https://developer.spotify.com/) account with an ads-enabled app
- A Spotify Ads ad account ID
- Python 3.8+ or `uv`. Required for the secure configuration helpers and automatic token refresh. Python is also used to check each request against the OpenAPI spec before it is sent; without it, that check is skipped. On Windows, ensure a real `python` or `py` is in your PATH (see [Troubleshooting](#troubleshooting)).
- Network access to `developer.spotify.com`, so each workflow can download the current Ads API OpenAPI document (see [How requests are made](#how-requests-are-made))
- [Git for Windows](https://gitforwindows.org/) (Windows only; provides Git Bash, which the token refresh hook requires)
- [jq](https://jqlang.org/) (recommended on Windows for richer hook output; the token refresh hook works without it but produces minimal JSON)

## Install

### Claude Code

```bash
claude plugin i spotify-ads-api
```

The plugin is installed from the [Official Anthropic marketplace](https://claude.com/plugins), which has auto-update enabled by default. Claude Code checks for plugin updates in the background after each session starts and applies them automatically. New versions take effect on your next launch (or run `/reload-plugins` to pick them up in the current session).

To use this repository as a custom marketplace in the Claude UI, choose **Add marketplace**, enter `spotify/ads-agentic-tools` or `https://github.com/spotify/ads-agentic-tools`, and select **Sync**. Then install **Spotify Ads API** from that marketplace. The Claude marketplace intentionally uses the repository-relative plugin source `"./"`; Git-based marketplace installs clone the whole repository and resolve that path from the repository root.

If you have auto-update disabled for the Official Anthropic marketplace, you will need to update the plugin manually. See the Anthropic instructions on [Discover and install plugins](https://code.claude.com/docs/en/discover-plugins) for instructions on managing marketplace updates.

### Codex

Add the Spotify Ads API plugin marketplace:

```bash
codex plugin marketplace add spotify/ads-agentic-tools
```

In the Codex app, you can instead choose **Add marketplace** and enter `https://github.com/spotify/ads-agentic-tools`. Restart Codex after adding the marketplace. Then open the plugin directory in the Codex app, or run `codex` and enter `/plugins` in the CLI. Select the added marketplace and install/enable **Spotify Ads API**.

Use `codex plugin marketplace upgrade` later to refresh installed marketplace sources.

### Antigravity CLI

```bash
agy plugin install https://github.com/spotify/ads-agentic-tools
```

Restart Antigravity CLI, then verify with `/plugins`. On Antigravity, skills activate automatically from natural language (or browse them with `/skills list`); run `/configure` for first-time setup instead of `/spotify-ads-api:configure`.

## Install from source

Use a source checkout for local development or testing unreleased changes.

1. Clone the repository (on Windows, disable `autocrlf` so the bash hooks stay LF-only):
   ```bash
   git clone -c core.autocrlf=false https://github.com/spotify/ads-agentic-tools.git
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

4. For Antigravity CLI, link the checkout as a local plugin:
   ```bash
   agy plugin link "$(pwd)"
   ```

   The link is a symlink, so source changes are picked up on the next Antigravity CLI restart.

The repository includes platform-specific marketplace metadata: `.agents/plugins/marketplace.json` for Codex and `.claude-plugin/marketplace.json` for Claude Code. Their plugin sources intentionally differ: Codex uses the public Git repository URL for this repository-root plugin, while Claude uses the relative string `"./"` required by its marketplace schema. Antigravity CLI has no marketplace file — it installs directly from the repository using the root `plugin.json` manifest. Keep all three manifests in sync when changing plugin metadata.

## Configure

### Team administrator: register the application

1. Create or select the team's Spotify Developer app:
   - Go to [developer.spotify.com](https://developer.spotify.com/) and log in
   - Click **Create App**
   - Enter a name (e.g. "Ads Agentic Tools") and a simple description
   - Under **Redirect URIs**, enter `http://127.0.0.1:8080/callback` and remember to click **Add**
   - Under **Which API/SDKs are you planning to use?**, check **Ads API**
   - Save the app and note its **Client ID**
   - Open [https://adsmanager.spotify.com/api-terms](https://adsmanager.spotify.com/api-terms) and make sure the ad account you want to use is selected. Accept the terms to authorize your client id to access your ad account through Ads API.

2. Share the client ID with the team's plugin users. A client ID is public
   application metadata; do not distribute an application secret. Keeping a
   team-owned client ID preserves that team's client-level attribution, quotas,
   and rate-limit isolation. The plugin has no global fallback client ID.

### Individual user: authorize the plugin

1. Configure OAuth with the team's client ID:
   ```
   /spotify-ads-api:configure
   ```
   (On Antigravity CLI, run `/configure` instead — the skill names below all apply, but the slash-command prefix is Claude Code/Codex syntax.)
   This opens your browser for PKCE authorization, then saves your tokens locally with automatic refresh. The authorization URL is also printed so it can be copied if the browser does not open automatically.

2. Create your first campaign:
   ```
   /spotify-ads-api:build-campaign Create an audio campaign called Summer Promo targeting US listeners aged 25-44 with $100/day budget
   ```

## Authentication

The plugin supports two authentication modes:

### OAuth 2.0 with PKCE (Recommended)
Run `/spotify-ads-api:configure` or `/spotify-ads-api:configure oauth [client_id]`. This launches Authorization Code with PKCE (`S256`) using Python 3 or `uv`. The verifier stays in memory, no application secret is requested, and tokens refresh automatically before API calls. The helper writes tokens directly to an atomically replaced mode-0600 settings file instead of printing them. If a managed workspace requires separate write approval, tokens remain in a private mode-0600 temporary file until a token-free finalization command succeeds. If automatic browser opening fails, copy the printed authorization URL while the callback listener remains active.

### Direct Token (Legacy)
Run `/spotify-ads-api:configure token`. The helper securely prompts for a pre-obtained access token without placing it in chat or command arguments. There is no automatic refresh, so the token expires in about one hour.

## Available Skills

Skill names below use Claude Code/Codex slash-command syntax. On Antigravity CLI, the same skills activate automatically from natural language (browse them with `/skills list`), and setup is `/configure`. You rarely need to name a skill: describing what you want is enough.

| Skill | Description |
|-------|-------------|
| `/spotify-ads-api:configure` | Set up OAuth credentials, ad account, and preferences |
| `/spotify-ads-api:campaigns` | List or get campaigns; stage creates and updates through drafts by default |
| `/spotify-ads-api:ads` | List or get ad sets and ads; stage creates and updates through drafts by default |
| `/spotify-ads-api:campaign-strategy` | Plan API-ready campaign structure and targeting from a landing page, business brief, or creative assets |
| `/spotify-ads-api:media-plan-to-draft` | Convert a spreadsheet, PDF, document, presentation, or third-party media plan into a reviewed and validated Spotify Ads draft |
| `/spotify-ads-api:build-campaign` | Create a full campaign hierarchy from a plain-text description |
| `/spotify-ads-api:drafts` | Default write workflow: stage new campaigns, ad sets, and ads (or changes to published ones) as drafts, validate them, and publish after explicit confirmation |
| `/spotify-ads-api:report` | Pull aggregate metrics, audience insights, or async CSV reports |
| `/spotify-ads-api:assets` | Upload, list, and manage creative assets |
| `/spotify-ads-api:audiences` | Upload customer lists and manage custom, engagement, event, and lookalike audiences |
| `/spotify-ads-api:measurement-setup` | Design and configure Pixel, CAPI, datasets, event mapping, advanced matching, mobile apps, and sharing |
| `/spotify-ads-api:measurement-debug` | Diagnose missing, stale, duplicated, mismatched, or unattributed Pixel/CAPI events |
| `/spotify-ads-api:account-admin` | Discover businesses/ad accounts and manage members, roles, invitations, and account details |
| `/spotify-ads-api:dashboard` | Quick performance overview of active campaigns |
| `/spotify-ads-api:monitor` | Diagnose pacing, delivery, stalled campaigns, and underdelivery issues; set up recurring checks when your host supports scheduled tasks |
| `/spotify-ads-api:export` | Export campaign hierarchy, targeting, budget, and optional metrics to CSV |
| `/spotify-ads-api:bulk` | Batch budget, archive, creative, and tracking changes, staged through drafts; batch pause, resume, and delivery changes for ad sets and ads, applied live after confirmation |
| `/spotify-ads-api:clone` | Clone campaigns or ad sets as validated drafts with optional changes |
| `/spotify-ads-api:change-history` | View a timeline of changes — who changed what, when, and how |

Two more components work in the background and have no slash command:

- **API reference** (`spotify-ads-api-reference`) loads automatically whenever you mention the Spotify Ads API. It gives the agent the live OpenAPI workflow and the API behaviors the spec does not describe.
- **Request builder agent** (`agents/spotify-ads-request-builder.md`) handles conversational requests that span several steps, such as campaign → ad set → ad, and passes IDs from one step to the next.

## Natural Language Examples

Ask for an outcome in ordinary language; you do not need to know endpoint names or request schemas. For example:

- **Plan and build:** “Recommend a Spotify campaign plan for this product page and a $5,000 budget.” or “Build an audio campaign for US listeners ages 25–44 and keep it as a validated draft.”
- **Operate at scale:** “Pause every active ad set in my summer campaign.” or “Clone last quarter’s campaign for next month.”
- **Measure performance:** “How are my active campaigns doing?” or “Export my campaign hierarchy and last-30-day metrics to CSV.”
- **Manage creative and audiences:** “Upload this MP3 as an audio creative.” or “Upload this customer list and create a custom audience.”
- **Set up and debug conversion tracking:** “Design Pixel and CAPI purchase tracking with deduplication.” or “Why did CAPI purchases stop arriving yesterday?”
- **Administer access:** “Audit who can access my ad account and which roles they have.”
- **Audit changes:** “What changed in my ad account this week?” or “Who changed the Summer Sale campaign?”

Contributors and internal testers can use the fuller [prompt catalog](tests/prompt-catalog.md), which pairs a natural user example with a behavioral probe for every skill. The [test scenarios](tests/test-scenarios.md) cover exact routing, schema, safety, and recovery expectations.

Campaign, ad set, and ad creation or modification is staged through the draft workflow by default, including requests that do not use the word “draft.” The plugin validates staged changes and publishes only after a separate request and explicit confirmation. Ask for an immediate or direct live change only when you intentionally want to bypass draft staging and your account permits published-entity writes. Pausing, resuming, or turning delivery on or off for ad sets and ads is the exception: drafts cannot carry delivery, so the plugin makes these changes live after you confirm them.

## How requests are made

- **Current API contract.** Before its first API call, each workflow downloads the current public [Ads API v3 OpenAPI document](https://developer.spotify.com/reference/ads-api/v3/api.yaml) and checks every planned request against it. If the document cannot be downloaded, the workflow stops before calling the API.
- **Checks before sending.** The request wrapper (`scripts/api-request.sh`) checks each request against that document before sending it. A request that can never succeed, for example one with a missing required field, a wrong type, or a read-only field, is not sent: it prints `ERROR: Request not sent.` and the problems it found. A field or value the spec does not define is sent anyway, with `WARNING: Sent anyway`. If no document has been downloaded, Python is not available, or the operation is not in the public spec, the request is sent without this check.
- **Safe retries.** Supported create requests carry an `Idempotency-Key` derived from the request, so if the same create is sent twice, the server treats the second as a repeat rather than creating a duplicate. The plugin never automatically retries a create or update that failed.
- **Usage attribution.** Every request includes an `X-Spotify-Ads-Sdk` header (the plugin's platform and version) and an `X-Spotify-Ads-Skill` header (the skill that made the call), so Spotify can measure usage and error rates per skill. On Claude Code and Codex, the token-refresh hook adds these headers to hand-written `curl` commands to the Ads API that lack them. If it has to guess the skill from the conversation, the value ends in `-inferred`. Antigravity's hooks cannot rewrite commands, so there it only warns.
- **Confirmations.** With `auto_execute: false`, the plugin shows each request and asks before running it. With `auto_execute: true`, it runs reads, reports, and draft creates and edits without asking, but always asks first before it publishes a draft, deletes a draft, makes a live change to delivery or spend (pause, resume, archive, budget, or bid), replaces a customer list or a media file used by active ads, or uses a start time that has already passed.

## Configuration Reference

Settings are stored in `.codex/spotify-ads-api.local.md` on Codex, `.claude/spotify-ads-api.local.md` on Claude, and `.agents/spotify-ads-api.local.md` on Antigravity. Each platform falls back to the other settings files if its preferred file does not exist. All three paths are gitignored.

| Field | Description | Default |
|-------|-------------|---------|
| `access_token` | OAuth2 bearer token | — |
| `refresh_token` | Token for automatic renewal | — |
| `token_expires_at` | ISO 8601 expiry timestamp | — |
| `client_id` | Spotify app client ID | — |
| `auth_flow` | `authorization_code_pkce` or `direct_token` | — |
| `ad_account_id` | Default ad account UUID | — |
| `environment` | API environment | `production` |
| `auto_execute` | Run reads, reports, and draft edits without asking (publishing, draft deletes, and live delivery or spend changes still ask; see [Confirmations](#how-requests-are-made)) | `false` |

Existing OAuth settings created before PKCE can keep using an unexpired access token, but cannot refresh. Run `/spotify-ads-api:configure` once to reauthorize. On macOS, the old `spotify-ads-api-client-secret` Keychain item is then unused and may be removed; the plugin does not delete it automatically.

Antigravity also loads [`ANTIGRAVITY.md`](ANTIGRAVITY.md) as plugin context. It covers settings, setup, tracking headers, and token expiry for that platform.

## Troubleshooting

**Expired token, a 401 response, or "Spotify OAuth refresh was rejected (invalid_grant)"**
If using OAuth, the plugin auto-refreshes tokens before API calls. If the refresh is rejected or the refresh token has expired, re-run `/spotify-ads-api:configure`. If using direct token mode, the token cannot refresh: obtain a new token and run `/spotify-ads-api:configure token`, then enter it at the secure terminal prompt. Settings created before PKCE can't refresh either; run `/spotify-ads-api:configure` once to reauthorize.

**404 errors on ad account requests**
The selected ad account ID may be incorrect. Verify your ad account UUID in Spotify Ads Manager, or ask the plugin to list your businesses and ad accounts after configuring a valid token.

**"ERROR: No settings file found. Run the configure skill first."**
Run `/spotify-ads-api:configure` to create the settings file.

**"ERROR: Request not sent."**
The request wrapper checked the request against the current OpenAPI document and found problems that would make the API reject it. Nothing reached the API, so it is safe to fix the listed fields and send the request again. `WARNING: Sent anyway` means the request was sent, but it included a field or value the spec does not define; check that you meant it.

**The OpenAPI document cannot be downloaded**
Workflows stop before any API call if they cannot download the current spec. Check that `developer.spotify.com` is reachable from your environment, including through any proxy or agent sandbox.

**"Min audience threshold was not met"**
Your targeting is too narrow for the selected ad format. The plugin will not resend the request or widen targeting on its own. It reports the narrow audience, suggests ways to broaden it (for example a wider age range, more locations or platforms, or a different ad format), and estimates again with the targeting you choose.

**"Asset stuck in PROCESSING"**
Large files may take longer to transcode. Check status with `/spotify-ads-api:assets get <id>`. If status is REJECTED, the file may not meet format requirements.

**"Python was not found" on Windows**
The `python3` command on stock Windows 11 is a Microsoft Store redirect stub, not real Python. It exits with code 49 and prints a Store install prompt. The plugin tries `python3` first on most code paths, and only checks that a Python command exists, not that it works, so it can pick up the stub. Install Python from [python.org](https://www.python.org/downloads/) or via `winget install Python.Python.3.13`, then turn off the `python.exe` and `python3.exe` App execution aliases under **Settings → Apps → Advanced app settings → App execution aliases**, so `python3` resolves to the real installation or is not found.

**Token refresh hook not running on Windows**
The hook (`hooks/check-token.sh`) is a bash script. On Windows it requires Git Bash, which is included with [Git for Windows](https://gitforwindows.org/). If the hook silently does nothing, ensure `bash.exe` is discoverable in your PATH (it should be after installing Git for Windows).

**Skill not activating on Antigravity CLI**
Run `/skills list` to confirm the plugin's skills loaded, and `/plugins` to confirm the plugin is enabled. Restart Antigravity CLI after installing or linking.

## Development

The plugin is markdown, shell, and standard-library Python with no build step. See [CONTRIBUTING.md](CONTRIBUTING.md) to run it from source and submit changes, and [AGENTS.md](AGENTS.md) for architecture and API conventions.

- **Regression tests:** [`tests/`](tests/README.md) has offline shell and Python suites for the hook, request wrapper, OpenAPI tooling, OAuth helpers, and marketplace metadata. They need no credentials or network.
- **Evals:** [`evals/`](evals/README.md) has behavior and language checks for the skills, run with `claude plugin eval` against recorded API responses.
- **Manual scenarios:** [`tests/test-scenarios.md`](tests/test-scenarios.md) and [`tests/prompt-catalog.md`](tests/prompt-catalog.md) cover end-to-end checks against a real ad account.

## License

Copyright 2026 Spotify, Inc.

Licensed under the Apache License, Version 2.0: https://www.apache.org/licenses/LICENSE-2.0

## Security Issues?

Please report sensitive security issues via Spotify's bug-bounty program (https://hackerone.com/spotify) rather than GitHub.
