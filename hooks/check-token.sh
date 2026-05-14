#!/bin/bash
set -uo pipefail

# Spotify Ads API PreToolUse hook
#
# Auto-refreshes expired OAuth tokens before API calls

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PLUGIN_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

if [ -n "${CODEX_PLUGIN_ROOT:-}" ] && [ -d "${CODEX_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CODEX_PLUGIN_ROOT"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
fi

PROJECT_DIR="${CODEX_PROJECT_DIR:-${CLAUDE_PROJECT_DIR:-$PWD}}"

find_settings_file() {
  local first_path second_path

  if [ -n "${CODEX_PROJECT_DIR:-}" ]; then
    first_path="$PROJECT_DIR/.codex/spotify-ads-api.local.md"
    second_path="$PROJECT_DIR/.claude/spotify-ads-api.local.md"
  elif [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
    first_path="$PROJECT_DIR/.claude/spotify-ads-api.local.md"
    second_path="$PROJECT_DIR/.codex/spotify-ads-api.local.md"
  else
    first_path="$PROJECT_DIR/.codex/spotify-ads-api.local.md"
    second_path="$PROJECT_DIR/.claude/spotify-ads-api.local.md"
  fi

  if [ -f "$first_path" ]; then
    printf '%s\n' "$first_path"
  elif [ -f "$second_path" ]; then
    printf '%s\n' "$second_path"
  fi
}

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

# Extract the bash command from tool input
command=$(printf '%s' "$input" | jq -r '.tool_input.command // .tool_input.cmd // .input.command // .input.cmd // ""')
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
  client_secret=$(security find-generic-password -a "spotify-ads-api" -s "spotify-ads-api-client-secret" -w 2>/dev/null || echo "")

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
      system_message="Spotify API token may be expired but no refresh credentials are configured. Run /spotify-ads-api:configure to set up OAuth."
    else
      REFRESH_SCRIPT="${PLUGIN_ROOT}/skills/configure/scripts/refresh-token.py"
      if refresh_result=$(python3 "$REFRESH_SCRIPT" \
        --client-id "$client_id" \
        --client-secret "$client_secret" \
        --refresh-token "$refresh_token" 2>/dev/null); then

        new_token=$(echo "$refresh_result" | jq -r '.access_token // ""')
        expires_in=$(echo "$refresh_result" | jq -r '.expires_in // 3600')
        new_refresh=$(echo "$refresh_result" | jq -r '.refresh_token // ""')

        if [ -n "$new_token" ]; then
          new_expires=$(date -u -v+"${expires_in}"S +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
                        date -u -d "+${expires_in} seconds" +"%Y-%m-%dT%H:%M:%SZ")

          update_setting() {
            local key="$1" val="$2" file="$3"
            sed -i '' "s|^${key}: .*|${key}: \"${val}\"|" "$file" 2>/dev/null || \
            sed -i "s|^${key}: .*|${key}: \"${val}\"|" "$file"
          }

          update_setting "access_token" "$new_token" "$SETTINGS_FILE"
          update_setting "token_expires_at" "$new_expires" "$SETTINGS_FILE"
          if [ -n "$new_refresh" ]; then
            update_setting "refresh_token" "$new_refresh" "$SETTINGS_FILE"
          fi

          if [ -n "$access_token" ]; then
            modified_command="${modified_command//$access_token/$new_token}"
          fi
          system_message="Spotify API token was expired and has been refreshed automatically."
        fi
      else
        system_message="Failed to refresh Spotify API token. Run /spotify-ads-api:configure to re-authenticate."
      fi
    fi
  fi
fi

# --- Emit output ---
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

exit 0
