#!/bin/bash
set -uo pipefail

# Spotify Ads API request wrapper
#
# Usage:
#   api-request.sh <skill> <METHOD> <path> [json_body]
#   api-request.sh --env
#
# Examples:
#   api-request.sh campaigns GET "ad_accounts/{ad_account_id}/campaigns?limit=50"
#   api-request.sh drafts POST "ad_accounts/{ad_account_id}/drafts/campaigns" '{"name":"My Campaign"}'
#   api-request.sh --env   # prints TOKEN, AD_ACCOUNT_ID, AUTO_EXECUTE, BASE_URL,
#                          # SDK_HEADER, PLUGIN_VERSION (and SKILL_HEADER when a
#                          # skill name is given). Output is eval-safe:
#                          # eval $(api-request.sh assets --env)

BASE_URL="https://api-partner.spotify.com/ads/v3"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PLUGIN_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

if [ -n "${CODEX_PLUGIN_ROOT:-}" ] && [ -d "${CODEX_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CODEX_PLUGIN_ROOT"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
fi

# --- Platform detection (mirrors check-token.sh) ---
if [ -n "${CODEX_PROJECT_DIR:-}" ]; then
  PLATFORM="codex"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  PLATFORM="claude"
else
  PLATFORM="antigravity"
fi

PROJECT_DIR="${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"

# --- Settings file discovery ---
find_settings_file() {
  local order dir candidate

  case "$PLATFORM" in
    antigravity) order=".agents .claude .codex" ;;
    claude) order=".claude .codex .agents" ;;
    *)      order=".codex .claude .agents" ;;
  esac

  for dir in $order; do
    candidate="$PROJECT_DIR/$dir/spotify-ads-api.local.md"
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
}

SETTINGS_FILE="$(find_settings_file || true)"

if [ -z "$SETTINGS_FILE" ] || [ ! -f "$SETTINGS_FILE" ]; then
  echo "ERROR: No settings file found. Run the configure skill first." >&2
  exit 1
fi

get_setting() {
  grep "^${1}:" "$SETTINGS_FILE" | head -1 | sed "s/^${1}: *//" | tr -d '"' | tr -d "'"
}

TOKEN=$(get_setting "access_token")
AD_ACCOUNT_ID=$(get_setting "ad_account_id")
AUTO_EXECUTE=$(get_setting "auto_execute")

if [ -z "$TOKEN" ]; then
  echo "ERROR: No access_token in settings file. Run the configure skill first." >&2
  exit 1
fi

# --- Plugin version from platform manifest ---
PLUGIN_VERSION=""
for manifest in "$PLUGIN_ROOT/.codex-plugin/plugin.json" \
                "$PLUGIN_ROOT/.claude-plugin/plugin.json" \
                "$PLUGIN_ROOT/plugin.json"; do
  if [ -f "$manifest" ]; then
    PLUGIN_VERSION=$(grep '"version"' "$manifest" | head -1 | sed 's/.*"version" *: *"\([^"]*\)".*/\1/')
    break
  fi
done

# --- SDK product name ---
case "$PLATFORM" in
  codex)  SDK_PRODUCT="codex-plugin" ;;
  claude) SDK_PRODUCT="claude-code-plugin" ;;
  *)      SDK_PRODUCT="antigravity-cli-plugin" ;;
esac

SDK_HEADER="X-Spotify-Ads-Sdk: ${SDK_PRODUCT}/${PLUGIN_VERSION}"

# --- --env mode: print settings and exit ---
#
# Values are single-quoted so `eval $(api --env)` assigns them intact. Unquoted,
# the space inside SDK_HEADER splits the assignment and eval treats every line
# as a prefix assignment to a bogus command, silently setting nothing at all.
if [ "${1:-}" = "--env" ] || [ "${2:-}" = "--env" ]; then
  ENV_SKILL="${1:-}"
  [ "$ENV_SKILL" = "--env" ] && ENV_SKILL=""

  print_env() {
    # Escape any embedded single quote so the value survives eval intact.
    printf "%s='%s'\n" "$1" "$(printf '%s' "$2" | sed "s/'/'\\\\''/g")"
  }

  print_env TOKEN "$TOKEN"
  print_env AD_ACCOUNT_ID "$AD_ACCOUNT_ID"
  print_env AUTO_EXECUTE "${AUTO_EXECUTE:-false}"
  print_env BASE_URL "$BASE_URL"
  print_env SDK_HEADER "$SDK_HEADER"
  print_env PLUGIN_VERSION "$PLUGIN_VERSION"
  if [ -n "$ENV_SKILL" ]; then
    print_env SKILL_HEADER "X-Spotify-Ads-Skill: $ENV_SKILL"
  fi
  exit 0
fi

# --- Parse arguments ---
if [ $# -lt 3 ]; then
  echo "Usage: api-request.sh <skill> <METHOD> <path> [json_body]" >&2
  echo "       api-request.sh --env" >&2
  exit 1
fi

SKILL="$1"
METHOD="$2"
PATH_ARG="$3"
BODY="${4:-}"

SKILL_HEADER="X-Spotify-Ads-Skill: ${SKILL}"

# --- Substitute {ad_account_id} in path ---
PATH_ARG="${PATH_ARG//\{ad_account_id\}/$AD_ACCOUNT_ID}"

URL="${BASE_URL}/${PATH_ARG}"

# --- Build and execute curl ---
CURL_ARGS=(-s -w "\nHTTP_STATUS:%{http_code}")
CURL_ARGS+=(-X "$METHOD")
CURL_ARGS+=(-H "Authorization: Bearer ${TOKEN}")
CURL_ARGS+=(-H "$SDK_HEADER")
CURL_ARGS+=(-H "$SKILL_HEADER")

if [ -n "$BODY" ]; then
  CURL_ARGS+=(-H "Content-Type: application/json")
  CURL_ARGS+=(-d "$BODY")
fi

exec curl "${CURL_ARGS[@]}" "$URL"
