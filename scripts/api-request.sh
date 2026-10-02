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

# --- Substitute {ad_account_id} in path and body ---
PATH_ARG="${PATH_ARG//\{ad_account_id\}/$AD_ACCOUNT_ID}"
BODY="${BODY//\{ad_account_id\}/$AD_ACCOUNT_ID}"

URL="${BASE_URL}/${PATH_ARG}"

# --- Build and execute curl ---
CURL_ARGS=(-s -w "\nHTTP_STATUS:%{http_code}")
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

# --- Eval replay mode ---
#
# For offline evals only (evals/README.md). When EVAL_ADS_API_FIXTURES names a
# fixture directory, answer from it instead of calling the API, and append the
# request to $EVAL_ADS_API_LOG so graders can check what was sent. A fixture is
# <key>.http: first line the HTTP status, the rest the response body. The key is
# METHOD__path with the query dropped, the ad account ID put back as
# {ad_account_id}, other UUIDs as {id}, and "/" as "__". An optional
# <key>.<n>.http answers the nth call to the same key. A request with no
# fixture gets a plain 404.
if [ -n "${EVAL_ADS_API_FIXTURES:-}" ]; then
  case "$EVAL_ADS_API_FIXTURES" in
    /*) FIXTURE_DIR="$EVAL_ADS_API_FIXTURES" ;;
    *)  FIXTURE_DIR="$PROJECT_DIR/$EVAL_ADS_API_FIXTURES" ;;
  esac
  LOG_FILE="${EVAL_ADS_API_LOG:-$PROJECT_DIR/ads-api-requests.log}"

  KEY_PATH="${PATH_ARG%%\?*}"
  ACCOUNT_PLACEHOLDER='{ad_account_id}'
  [ -n "$AD_ACCOUNT_ID" ] && KEY_PATH="${KEY_PATH//"$AD_ACCOUNT_ID"/$ACCOUNT_PLACEHOLDER}"
  KEY_PATH=$(printf '%s' "$KEY_PATH" \
    | sed -E 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/{id}/g; s#/#__#g')
  KEY="${METHOD}__${KEY_PATH}"

  CALL_N=1
  if [ -f "$LOG_FILE" ]; then
    CALL_N=$(( $(awk -v k="$KEY " 'index($0, k) == 1' "$LOG_FILE" | wc -l) + 1 ))
  fi
  printf '%s %s %s\n' "$KEY" "$PATH_ARG" "$(printf '%s' "$BODY" | tr '\n' ' ')" >> "$LOG_FILE"

  FIXTURE="$FIXTURE_DIR/${KEY}.${CALL_N}.http"
  [ -f "$FIXTURE" ] || FIXTURE="$FIXTURE_DIR/${KEY}.http"
  if [ ! -f "$FIXTURE" ]; then
    # Look like a real API 404 so the agent under test can't tell it's in an eval.
    # The request log above already records the key that had no fixture.
    printf '{"messages":["Not found"],"error_codes":[{"code":"NOT_FOUND","definition":"NOT_FOUND"}]}\nHTTP_STATUS:404\n'
    exit 0
  fi
  tail -n +2 "$FIXTURE"
  printf '\nHTTP_STATUS:%s\n' "$(head -1 "$FIXTURE" | tr -d '[:space:]')"
  exit 0
fi

exec curl "${CURL_ARGS[@]}" "$URL"
