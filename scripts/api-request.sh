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
CLIENT_ID=$(get_setting "client_id")

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
NO_DEDUP_KEY=false
SKILL="$1"
shift

if [ "${1:-}" = "--no-dedup-key" ]; then
  NO_DEDUP_KEY=true
  shift
fi

if [ $# -lt 2 ]; then
  echo "Usage: api-request.sh <skill> [--no-dedup-key] <METHOD> <path> [json_body]" >&2
  echo "       api-request.sh --env" >&2
  exit 1
fi

METHOD="$1"
PATH_ARG="$2"
BODY="${3:-}"

SKILL_HEADER="X-Spotify-Ads-Skill: ${SKILL}"

# --- Substitute {ad_account_id} in path ---
PATH_ARG="${PATH_ARG//\{ad_account_id\}/$AD_ACCOUNT_ID}"

URL="${BASE_URL}/${PATH_ARG}"

# --- Build and execute curl ---
CURL_ARGS=(-s)
CURL_ARGS+=(-X "$METHOD")
CURL_ARGS+=(-H "Authorization: Bearer ${TOKEN}")
CURL_ARGS+=(-H "$SDK_HEADER")
CURL_ARGS+=(-H "$SKILL_HEADER")

# --- Auto-inject dedup key for supported create endpoints ---
if [ "$METHOD" = "POST" ] && [ "$NO_DEDUP_KEY" = "false" ]; then
  RESOLVED_PATH="${PATH_ARG%%\?*}"
  if printf '%s' "$RESOLVED_PATH" | grep -qE "^ad_accounts/[^/]+/(drafts/)?(campaigns|ad_sets|ads)$"; then
    DEDUP_KEY=$(python3 "$SCRIPT_DIR/canonical-hash.py" "$BODY" "$BASE_URL" "$RESOLVED_PATH" "$METHOD" "$CLIENT_ID" 2>/dev/null \
      || uv run "$SCRIPT_DIR/canonical-hash.py" "$BODY" "$BASE_URL" "$RESOLVED_PATH" "$METHOD" "$CLIENT_ID" 2>/dev/null \
      || printf '%s' "${BASE_URL}|${METHOD}|${RESOLVED_PATH}|${CLIENT_ID}|${BODY}" | shasum -a 256 | cut -d' ' -f1)
    CURL_ARGS+=(-H "Idempotency-Key: ${DEDUP_KEY}")
  fi
fi

if [ -n "$BODY" ]; then
  CURL_ARGS+=(-H "Content-Type: application/json")
  CURL_ARGS+=(-d "$BODY")
fi

# --- Execute and emit the documented `body\nHTTP_STATUS:<code>` output ---
#
# The body is spooled to a temp file so the status line can be computed before
# the rest of stdout is written. When the 403 response body says the client ID
# is not allow-listed (observed shape: "Client ID <id> is not allow-listed"),
# append an ADS_API_HINT naming the API terms page — the only fix is accepting
# the terms at https://adsmanager.spotify.com/api-terms with the target ad
# account selected (see README, "Team administrator: register the
# application"). Without the hint, agents invent a developer-dashboard
# request flow that does not exist.
#
# The hint is keyed to that body marker, NOT to the bare 403 status: other 403s
# (wrong ad account, insufficient role, fetching data the token is not
# authorized for) are ordinary permission denials and must not carry allow-list
# guidance. The marker is specific enough to apply regardless of HTTP method.
BODY_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE"' EXIT

HTTP_CODE="$(curl "${CURL_ARGS[@]}" -o "$BODY_FILE" -w '%{http_code}' "$URL")"
CURL_EXIT=$?

# A curl transport failure (timeout, DNS, refused connection) prints no status;
# keep parity with the old `exec curl` behaviour and exit without a status line.
if [ -z "$HTTP_CODE" ]; then
  exit "$CURL_EXIT"
fi

cat "$BODY_FILE"
printf '\nHTTP_STATUS:%s\n' "$HTTP_CODE"

if [ "$HTTP_CODE" = "403" ] && grep -qiE 'not allow[-_ ]?listed|client[ _-]?id.*allow[ _-]?list' "$BODY_FILE"; then
  printf 'ADS_API_HINT: This 403 says the client ID is not allow-listed for the Ads API. Open https://adsmanager.spotify.com/api-terms with the target ad account selected and accept the API terms; the saved OAuth tokens remain valid, so after accepting, retry the same call without reconfiguring. Always mention this page to the user.\n'
fi

exit "$CURL_EXIT"
