# Spotify Ads API Extension

Manage Spotify ad campaigns with natural language. Capabilities are packaged as Agent Skills (campaigns, ads, assets, reporting, dashboards, monitoring, bulk operations, cloning, exports, and a full campaign builder). Describe what you want — e.g. "show my campaign dashboard" or "create a campaign for my podcast" — or run `/skills list` to see everything available.

## Settings

Read and write per-user configuration in `.gemini/spotify-ads-api.local.md` (YAML frontmatter: `access_token`, `refresh_token`, `token_expires_at`, `client_id`, `ad_account_id`, `environment`, `auto_execute`). If that file does not exist, fall back to `.claude/spotify-ads-api.local.md`, then `.codex/spotify-ads-api.local.md`.

Never commit these files. The `client_secret` is stored in the macOS Keychain (service: `spotify-ads-api-client-secret`, account: `spotify-ads-api`), not in the settings file.

## First-Time Setup

Run `/configure` (or ask to "configure Spotify Ads API credentials") to set up OAuth 2.0 authentication and select an ad account. Documentation elsewhere may reference `/spotify-ads-api:configure` — that is the Claude Code/Codex name for the same configure skill.

## SDK Tracking Header

Every Spotify Ads API request must include the SDK tracking header. Read the `version` from this extension's `gemini-extension.json` and set:

```bash
SDK_HEADER="X-Spotify-Ads-Sdk: gemini-cli-extension/$PLUGIN_VERSION"
```

Include `-H "$SDK_HEADER"` on all curl commands to `api-partner.spotify.com`.

## Token Expiry

A BeforeTool hook refreshes expired OAuth tokens automatically before API calls. Gemini CLI auto-discovers hooks at the fixed path `hooks/hooks.json`, but the file ships as `hooks/gemini-hooks.json` to avoid conflicts with Claude Code's hook loader. After installing the extension, activate the hook once:

```bash
cp hooks/gemini-hooks.json hooks/hooks.json
```

If a request still returns 401, refresh the token per the configure skill's instructions or re-run `/configure`.

## Contributors

If you are editing this repository itself (not using the extension), `AGENTS.md` is the canonical instruction file — read it before making changes.
