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

# Need jq for JSON parsing
if ! command -v jq &>/dev/null; then
  exit 0
fi

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

# Extract the command from tool input (different field paths per platform)
# Claude/Codex: .tool_input.command
# Antigravity:  .toolCall.args.CommandLine
command=$(printf '%s' "$input" | jq -r '
  .tool_input.command //
  .tool_input.cmd //
  .input.command //
  .input.cmd //
  .toolCall.args.CommandLine //
  .toolCall.args.command //
  ""')
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
  auth_flow=$(get_setting "auth_flow")

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

  if [ "$auth_flow" = "authorization_code_pkce" ] && [ "$needs_refresh" = true ]; then
    if [ -z "$refresh_token" ] || [ -z "$client_id" ]; then
      system_message="Spotify API token is expired but PKCE refresh settings are incomplete. Run the configure skill (/spotify-ads-api:configure on Claude/Codex, /configure on Antigravity) to authorize again."
    elif ! command -v python3 &>/dev/null; then
      system_message="Spotify API token is expired, but Python 3 is required for automatic PKCE refresh. Install Python 3 or run the configure skill to authorize again."
    else
      REFRESH_SCRIPT="${PLUGIN_ROOT}/skills/configure/scripts/refresh-token.py"
      if refresh_result=$(python3 "$REFRESH_SCRIPT" \
        --client-id "$client_id" \
        --refresh-token "$refresh_token" 2>/dev/null); then

        new_token=$(echo "$refresh_result" | jq -r '.access_token // ""')
        expires_in=$(echo "$refresh_result" | jq -r 'if (.expires_in | type) == "number" then .expires_in else 3600 end')
        new_refresh=$(echo "$refresh_result" | jq -r '.refresh_token // ""')

        if [ -n "$new_token" ]; then
          new_expires=$(date -u -v+"${expires_in}"S +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                        date -u -d "+${expires_in} seconds" +"%Y-%m-%dT%H:%M:%SZ")

          # Replace all OAuth values in one atomic rename. If Spotify omits a
          # rotated refresh token, retain the existing value.
          effective_refresh="${new_refresh:-$refresh_token}"
          tmp="${SETTINGS_FILE}.tmp.$$"
          if (umask 077; ACCESS_TOKEN="$new_token" TOKEN_EXPIRES_AT="$new_expires" REFRESH_TOKEN="$effective_refresh" awk '
              BEGIN {
                access=ENVIRON["ACCESS_TOKEN"]
                expires=ENVIRON["TOKEN_EXPIRES_AT"]
                refresh=ENVIRON["REFRESH_TOKEN"]
              }
              /^access_token: / && !seen_access { print "access_token: \""access"\""; seen_access=1; next }
              /^token_expires_at: / && !seen_expires { print "token_expires_at: \""expires"\""; seen_expires=1; next }
              /^refresh_token: / && !seen_refresh { print "refresh_token: \""refresh"\""; seen_refresh=1; next }
              { print }
            ' "$SETTINGS_FILE" > "$tmp") && mv "$tmp" "$SETTINGS_FILE"; then
            if [ -n "$access_token" ]; then
              set -f
              modified_command="${modified_command//"$access_token"/$new_token}"
              set +f
            fi
            system_message="Spotify API token was expired and has been refreshed automatically. Re-read the access_token from the settings file before retrying."
          else
            rm -f "$tmp"
            system_message="Spotify API token refreshed, but the settings file could not be updated atomically. Run the configure skill before retrying."
          fi
        else
          system_message="Spotify token refresh returned no access token. Run the configure skill to authorize again."
        fi
      else
        refresh_status=$?
        if [ "$refresh_status" -eq 1 ]; then
          system_message="Spotify OAuth refresh was rejected (invalid_grant). Run the configure skill (/spotify-ads-api:configure on Claude/Codex, /configure on Antigravity) to authorize again."
        else
          system_message="Failed to refresh Spotify API token. Run the configure skill (/spotify-ads-api:configure on Claude/Codex, /configure on Antigravity) to authorize again."
        fi
      fi
    fi
  elif [ "$auth_flow" = "direct_token" ] && [ "$needs_refresh" = true ]; then
    system_message="This direct Spotify API token is expired or has no expiry metadata and cannot refresh automatically. Configure OAuth with PKCE or provide a new direct token."
  elif [ -z "$auth_flow" ]; then
    if [ "$needs_refresh" = true ]; then
      system_message="This legacy Spotify OAuth configuration is expired and cannot refresh without reauthorization. Run the configure skill to migrate to PKCE."
    else
      system_message="Legacy Spotify OAuth configuration detected. The current token can be used until it expires; run the configure skill once to migrate to PKCE."
    fi
  fi
fi

# --- Emit output ---
# Claude/Codex: permissionDecision + updatedInput to rewrite the command.
# Antigravity: decision + reason (no command rewriting support).
if [ "$PLATFORM" = "antigravity" ]; then
  if [ -n "$system_message" ]; then
    jq -n --arg msg "$system_message" '{
      "decision": "allow",
      "reason": $msg
    }' 2>/dev/null
  fi
else
  if [[ "$modified_command" != "$command" ]]; then
    if [ -n "$system_message" ]; then
      jq -n --arg cmd "$modified_command" --arg msg "$system_message" '{
        "hookSpecificOutput": {
          "permissionDecision": "allow",
          "updatedInput": {"command": $cmd}
        },
        "systemMessage": $msg
      }' 2>/dev/null
    else
      jq -n --arg cmd "$modified_command" '{
        "hookSpecificOutput": {
          "permissionDecision": "allow",
          "updatedInput": {"command": $cmd}
        }
      }' 2>/dev/null
    fi
  elif [ -n "$system_message" ]; then
    jq -n --arg msg "$system_message" '{"systemMessage": $msg}' 2>/dev/null
  fi
fi

exit 0
