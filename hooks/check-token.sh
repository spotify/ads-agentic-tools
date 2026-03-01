#!/bin/bash
set -uo pipefail

# Spotify Ads API token refresh hook (PreToolUse:Bash)
#
# Fast path: exits 0 immediately for any command that doesn't target
# the Spotify API. Only does work when the command contains
# api-partner.spotify.com AND the token is expired.

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
command=$(echo "$input" | jq -r '.tool_input.command // ""')
if [[ -z "$command" ]] || [[ "$command" != *"api-partner.spotify.com"* ]]; then
  exit 0
fi

# Locate settings file
SETTINGS_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/spotify-ads-api.local.md"
if [ ! -f "$SETTINGS_FILE" ]; then
  exit 0
fi

# Parse a single value from YAML frontmatter
get_setting() {
  grep "^${1}:" "$SETTINGS_FILE" | head -1 | sed "s/^${1}: *//" | tr -d '"' | tr -d "'"
}

access_token=$(get_setting "access_token")
token_expires_at=$(get_setting "token_expires_at")
refresh_token=$(get_setting "refresh_token")
client_id=$(get_setting "client_id")
client_secret=$(get_setting "client_secret")

# Determine if token needs refresh
needs_refresh=false

if [ -z "$token_expires_at" ]; then
  # Missing or empty expiry — treat as expired
  needs_refresh=true
else
  # Parse expiry to epoch (macOS then Linux)
  expires_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$token_expires_at" +%s 2>/dev/null || \
                  date -d "$token_expires_at" +%s 2>/dev/null || \
                  echo "0")
  now_epoch=$(date +%s)
  if [ "$now_epoch" -ge "$expires_epoch" ]; then
    needs_refresh=true
  fi
fi

if [ "$needs_refresh" = false ]; then
  exit 0
fi

# Cannot refresh without credentials
if [ -z "$refresh_token" ] || [ -z "$client_id" ] || [ -z "$client_secret" ]; then
  echo '{"systemMessage": "Spotify API token may be expired but no refresh credentials are configured. Run /spotify-ads-api:configure to set up OAuth."}'
  exit 0
fi

# Run the refresh script
REFRESH_SCRIPT="${CLAUDE_PLUGIN_ROOT}/skills/configure/scripts/refresh-token.py"
refresh_result=$(python3 "$REFRESH_SCRIPT" \
  --client-id "$client_id" \
  --client-secret "$client_secret" \
  --refresh-token "$refresh_token" 2>/dev/null) || {
  echo '{"systemMessage": "Failed to refresh Spotify API token. Run /spotify-ads-api:configure to re-authenticate."}'
  exit 0
}

# Parse refresh output
new_token=$(echo "$refresh_result" | jq -r '.access_token // ""')
expires_in=$(echo "$refresh_result" | jq -r '.expires_in // 3600')
new_refresh=$(echo "$refresh_result" | jq -r '.refresh_token // ""')

if [ -z "$new_token" ]; then
  exit 0
fi

# Calculate new expiry (macOS then Linux)
new_expires=$(date -u -v+"${expires_in}"S +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || \
              date -u -d "+${expires_in} seconds" +"%Y-%m-%dT%H:%M:%SZ")

# Update settings file (macOS sed -i '' vs Linux sed -i)
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

# Substitute the old token with the new one in the curl command
new_command="${command//$access_token/$new_token}"

# Return updated tool input so the command runs with the fresh token
jq -n --arg cmd "$new_command" '{
  "hookSpecificOutput": {
    "permissionDecision": "allow",
    "updatedInput": {"command": $cmd}
  },
  "systemMessage": "Spotify API token was expired and has been refreshed automatically."
}'

exit 0
