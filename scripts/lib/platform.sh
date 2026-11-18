#!/bin/bash
# Shared platform detection, sourced by scripts/api-request.sh (the agent's shell)
# and hooks/check-token.sh (the hook process). Both must agree, or the hook could
# refresh a different settings file than the one requests read, and attribution
# would report a different SDK product for the same call.
#
# Interface
#   detect_platform [hint]
#     hint    "codex" or "cursor" when the hook payload itself identifies the
#             platform; empty in the shell
#     SPOTIFY_ADS_PLATFORM, when set to a known platform, wins over everything.
#     The hook sets it for its own api-request.sh --env call, because only the
#     hook can see the payload (Codex hooks carry no CODEX_* variable at all).
#     Sets    PLATFORM     codex | cursor | copilot | claude | antigravity
#             PROJECT_DIR  the workspace holding the settings file
#   settings_dirs
#     Prints the settings directories for PLATFORM, most preferred first.
#   sdk_product
#     Prints the X-Spotify-Ads-Sdk product name for PLATFORM.
#
# Explicit *_PROJECT_DIR vars win over the shell markers, which a nested agent can
# inherit from its parent (e.g. Claude Code started from a Codex shell). Cursor
# and Copilot also set CLAUDE_PROJECT_DIR in their hooks for Claude
# compatibility, so their own variables are checked before it.
#
# Hook process markers:
#   Codex    none; its payload has a top-level turn_id (passed as hint "codex")
#   Cursor   CURSOR_PROJECT_DIR; its payload has cursor_version (hint "cursor")
#   Copilot  COPILOT_PROJECT_DIR
#   Claude   CLAUDE_PROJECT_DIR
# Agent shell markers:
#   Codex    CODEX_THREAD_ID or CODEX_SESSION_ID (never CODEX_PROJECT_DIR, which
#            is kept for overrides)
#   Claude   CLAUDECODE=1
#   Cursor   CURSOR_AGENT=1
#   Copilot  COPILOT_CLI=1
# Antigravity sets no known marker, so it is the default.

detect_platform() {
  local hint="${1:-}"

  case "${SPOTIFY_ADS_PLATFORM:-}" in
    codex|cursor|copilot|claude|antigravity) PLATFORM="$SPOTIFY_ADS_PLATFORM" ;;
    *) detect_platform_from_env "$hint" ;;
  esac

  PROJECT_DIR="${CODEX_PROJECT_DIR:-${CURSOR_PROJECT_DIR:-${COPILOT_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}}}"
}

detect_platform_from_env() {
  local hint="$1"

  if [ -n "${CODEX_PROJECT_DIR:-}" ] || [ "$hint" = codex ]; then
    PLATFORM="codex"
  elif [ -n "${CURSOR_PROJECT_DIR:-}" ] || [ "$hint" = cursor ]; then
    PLATFORM="cursor"
  elif [ -n "${COPILOT_PROJECT_DIR:-}" ]; then
    PLATFORM="copilot"
  elif [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    PLATFORM="claude"
  elif [ -n "${CODEX_THREAD_ID:-}" ] || [ -n "${CODEX_SESSION_ID:-}" ]; then
    PLATFORM="codex"
  elif [ "${CLAUDECODE:-}" = "1" ]; then
    PLATFORM="claude"
  elif [ "${CURSOR_AGENT:-}" = "1" ]; then
    PLATFORM="cursor"
  elif [ "${COPILOT_CLI:-}" = "1" ]; then
    PLATFORM="copilot"
  else
    PLATFORM="antigravity"
  fi
}

# Cursor and Copilot have no settings directory of their own that is safe for
# secrets (.github/ is committed, and .cursor/ often is), so they share .agents/.
settings_dirs() {
  case "$PLATFORM" in
    claude) printf '%s\n' ".claude .codex .agents" ;;
    codex)  printf '%s\n' ".codex .claude .agents" ;;
    *)      printf '%s\n' ".agents .claude .codex" ;;
  esac
}

sdk_product() {
  case "$PLATFORM" in
    codex)   printf '%s\n' "codex-plugin" ;;
    claude)  printf '%s\n' "claude-code-plugin" ;;
    cursor)  printf '%s\n' "cursor-plugin" ;;
    copilot) printf '%s\n' "copilot-cli-plugin" ;;
    *)       printf '%s\n' "antigravity-cli-plugin" ;;
  esac
}
