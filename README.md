# spotify-ads-api

A Claude Code plugin for the Spotify Ads API v3. Translates natural language into correct REST API calls for managing campaigns, ad sets, ads, assets, audiences, and reporting on Spotify's advertising platform.

## Features

- Natural language to API call translation ("Create a campaign called Summer Sale with a reach objective")
- Full CRUD operations on campaigns, ad sets, ads, assets, and audiences
- Aggregate, insight, and async CSV reporting
- Configurable sandbox/production environment
- Preview-before-execute or auto-execute modes

## Prerequisites

- A Spotify Ads API access token ([Spotify for Developers](https://developer.spotify.com/))
- An ad account ID
- Claude Code CLI

## Installation

```bash
claude --plugin-dir /path/to/sp-ads-api-plugin
```

## Setup

Run the configure command to set your credentials:

```
/spotify-ads-api:configure
```

This creates `.claude/spotify-ads-api.local.md` with your access token, ad account ID, environment preference, and execution mode.

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `/spotify-ads-api:configure` | Set up API credentials and preferences |
| `/spotify-ads-api:campaigns` | List, create, get, or update campaigns |
| `/spotify-ads-api:ads` | Manage ad sets and ads |
| `/spotify-ads-api:report` | Pull aggregate, insight, or async reports |

### Natural Language

The plugin includes an agent that interprets natural language requests:

- "Create a campaign called Summer Sale with a reach objective"
- "Set up an audio ad targeting 18-34 year olds in the US with $50/day budget"
- "Show me how my campaigns performed last month"
- "Pause the Summer Sale campaign"
- "Pull a report on impressions and spend for all active campaigns"

### API Reference

The plugin includes a comprehensive API reference skill that activates automatically when you mention the Spotify Ads API. It covers:

- All public endpoints (campaigns, ad sets, ads, assets, audiences, reports, targeting)
- Request/response schemas with field types and constraints
- Enum values for status fields, formats, targeting options
- Budget micro-amount conversion ($1 = 1,000,000 micro-units)

## Configuration

Settings are stored in `.claude/spotify-ads-api.local.md`:

```yaml
access_token: "your-token-here"
ad_account_id: "your-account-uuid"
environment: "sandbox"    # or "production"
auto_execute: false       # true to skip confirmation prompts
```

## API Reference

- **Base URLs**:
  - Sandbox: `https://api-partner.spotify.com/ads-sandbox/v3`
  - Production: `https://api-partner.spotify.com/ads/v3`
- **Auth**: Bearer token in Authorization header
- **Resource hierarchy**: Business > Ad Account > Campaign > Ad Set > Ad

## License

MIT
