#!/bin/bash
set -uo pipefail

# Spotify Ads API pre-tool hook (PreToolUse on Claude/Codex/Antigravity)
#
# Auto-refreshes expired OAuth tokens before API calls.
# Claude/Codex payload: .tool_input.command; supports command rewriting.
# Antigravity payload: .toolCall.args.CommandLine; decision allow/deny only (no rewrite).

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PLUGIN_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

if [ -n "${CODEX_PLUGIN_ROOT:-}" ] && [ -d "${CODEX_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CODEX_PLUGIN_ROOT"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
fi

# Read all stdin (hook input JSON)
input=$(cat)

# Fast path: skip if not a Spotify API call
if [[ "$input" != *"api-partner.spotify.com"* ]]; then
  exit 0
fi

# Prefer jq for JSON; fall back to grep/sed for minimal parsing
HAS_JQ=false
if command -v jq &>/dev/null; then
  HAS_JQ=true
fi

json_extract_string() {
  printf '%s' "$1" | sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# Detect platform from env vars; Antigravity sets none of the known
# *_PROJECT_DIR vars, so it falls through to the default.
if [ -n "${CODEX_PROJECT_DIR:-}" ]; then
  PLATFORM="codex"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  PLATFORM="claude"
else
  PLATFORM="antigravity"
fi

PROJECT_DIR="${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"

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

find_python() {
  local cmd candidates
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) candidates="py python python3" ;;
    *)                     candidates="python3 python py" ;;
  esac
  for cmd in $candidates; do
    if command -v "$cmd" &>/dev/null && "$cmd" -c "import sys" &>/dev/null; then
      printf '%s\n' "$cmd"
      return
    fi
  done
}
PYTHON="$(find_python || true)"

# Extract the command from tool input (different field paths per platform)
# Claude/Codex: .tool_input.command
# Antigravity:  .toolCall.args.CommandLine
if [ "$HAS_JQ" = true ]; then
  command=$(printf '%s' "$input" | jq -r '
    .tool_input.command //
    .tool_input.cmd //
    .input.command //
    .input.cmd //
    .toolCall.args.CommandLine //
    .toolCall.args.command //
    ""')
else
  command=$(json_extract_string "$input" "command")
  if [ -z "$command" ]; then
    command=$(json_extract_string "$input" "cmd")
  fi
  if [ -z "$command" ]; then
    command=$(json_extract_string "$input" "CommandLine")
  fi
fi
if [[ -z "$command" ]] || [[ "$command" != *"api-partner.spotify.com"* ]]; then
  exit 0
fi

# Start with the original command; will be modified as needed
modified_command="$command"
system_message=""

# --- Locate settings file and attempt token refresh ---
SETTINGS_FILE="$(find_settings_file || true)"

if [ -n "$SETTINGS_FILE" ] && [ -f "$SETTINGS_FILE" ]; then
  # Parse a single value from YAML frontmatter
  get_setting() {
    grep "^${1}:" "$SETTINGS_FILE" | head -1 | sed "s/^${1}: *//" | tr -d '"' | tr -d "'"
  }

  access_token=$(get_setting "access_token")
  token_expires_at=$(get_setting "token_expires_at")
  refresh_token=$(get_setting "refresh_token")
  client_id=$(get_setting "client_id")
  if [ -n "$PYTHON" ]; then
    client_secret=$($PYTHON "$PLUGIN_ROOT/scripts/credential-helper.py" get 2>/dev/null || echo "")
  else
    client_secret=$(security find-generic-password -a "spotify-ads-api" -s "spotify-ads-api-client-secret" -w 2>/dev/null || echo "")
  fi

  # Determine if token needs refresh
  needs_refresh=false

  if [ -z "$token_expires_at" ]; then
    needs_refresh=true
  else
    expires_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$token_expires_at" +%s 2>/dev/null || \
                    date -d "$token_expires_at" +%s 2>/dev/null || \
                    echo "0")
    now_epoch=$(date +%s)
    if [ "$now_epoch" -ge "$expires_epoch" ]; then
      needs_refresh=true
    fi
  fi

  if [ "$needs_refresh" = true ]; then
    if [ -z "$refresh_token" ] || [ -z "$client_id" ] || [ -z "$client_secret" ]; then
      system_message="Spotify API token may be expired but no refresh credentials are configured. Run the configure skill (/spotify-ads-api:configure on Claude/Codex, /configure on Antigravity) to set up OAuth."
    else
      REFRESH_SCRIPT="${PLUGIN_ROOT}/skills/configure/scripts/refresh-token.py"
      if [ -z "$PYTHON" ]; then
        system_message="Python is required for token refresh but was not found. Install Python 3.8+ and ensure python3, python, or py is in your PATH."
      elif refresh_result=$($PYTHON "$REFRESH_SCRIPT" \
        --client-id "$client_id" \
        --client-secret "$client_secret" \
        --refresh-token "$refresh_token" 2>/dev/null); then

        if [ "$HAS_JQ" = true ]; then
          new_token=$(echo "$refresh_result" | jq -r '.access_token // ""')
          expires_in=$(echo "$refresh_result" | jq -r '.expires_in // 3600')
          new_refresh=$(echo "$refresh_result" | jq -r '.refresh_token // ""')
        else
          new_token=$(json_extract_string "$refresh_result" "access_token")
          expires_in=$(printf '%s' "$refresh_result" | sed -n 's/.*"expires_in"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' | head -1)
          expires_in=${expires_in:-3600}
          new_refresh=$(json_extract_string "$refresh_result" "refresh_token")
        fi

        if [ -n "$new_token" ]; then
          new_expires=$(date -u -v+"${expires_in}"S +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                        date -u -d "+${expires_in} seconds" +"%Y-%m-%dT%H:%M:%SZ")

          # Replace "key: ..." line in settings file via awk to avoid sed metacharacter injection
          update_setting() {
            local key="$1" val="$2" file="$3"
            local tmp="${file}.tmp.$$"
            AWK_KEY="$key" AWK_VAL="$val" awk '
              BEGIN { k=ENVIRON["AWK_KEY"]; v=ENVIRON["AWK_VAL"]; found=0 }
              { if ($0 ~ "^"k": " && !found) { print k": \""v"\""; found=1 } else print }
            ' "$file" > "$tmp" && mv "$tmp" "$file"
          }

          update_setting "access_token" "$new_token" "$SETTINGS_FILE"
          update_setting "token_expires_at" "$new_expires" "$SETTINGS_FILE"
          if [ -n "$new_refresh" ]; then
            update_setting "refresh_token" "$new_refresh" "$SETTINGS_FILE"
          fi

          if [ -n "$access_token" ]; then
            set -f
            modified_command="${modified_command//"$access_token"/$new_token}"
            set +f
          fi
          system_message="Spotify API token was expired and has been refreshed automatically. Re-read the access_token from the settings file before retrying."
        fi
      else
        system_message="Failed to refresh Spotify API token. Run the configure skill (/spotify-ads-api:configure on Claude/Codex, /configure on Antigravity) to re-authenticate."
      fi
    fi
  fi
fi

# --- Emit output ---
# Claude/Codex: permissionDecision + updatedInput to rewrite the command.
# Antigravity: decision + reason (no command rewriting support).

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | tr -d '\n'
}

emit_json() {
  if [ "$HAS_JQ" = true ]; then
    printf '%s' "$1" | jq . 2>/dev/null || printf '%s\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}

if [ "$PLATFORM" = "antigravity" ]; then
  if [ -n "$system_message" ]; then
    emit_json "{\"decision\":\"allow\",\"reason\":\"$(json_escape "$system_message")\"}"
  fi
else
  if [[ "$modified_command" != "$command" ]]; then
    if [ -n "$system_message" ]; then
      emit_json "{\"hookSpecificOutput\":{\"permissionDecision\":\"allow\",\"updatedInput\":{\"command\":\"$(json_escape "$modified_command")\"}},\"systemMessage\":\"$(json_escape "$system_message")\"}"
    else
      emit_json "{\"hookSpecificOutput\":{\"permissionDecision\":\"allow\",\"updatedInput\":{\"command\":\"$(json_escape "$modified_command")\"}}}"
    fi
  elif [ -n "$system_message" ]; then
    emit_json "{\"systemMessage\":\"$(json_escape "$system_message")\"}"
  fi
fi

exit 0
