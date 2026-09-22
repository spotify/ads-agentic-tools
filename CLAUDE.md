# CLAUDE.md

`AGENTS.md` is the canonical instruction file for this repository. Claude Code should read and follow `AGENTS.md` before making changes.

For every standard Spotify Ads API v3 request in a skill, agent, documentation example, or test scenario, use the shared `api()` helper backed by `scripts/api-request.sh`. Do not add expanded raw HTTP-client commands. The only exceptions are the asset-upload and OAuth transport operations explicitly documented in `AGENTS.md`.
