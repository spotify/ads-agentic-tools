#!/bin/bash
set -uo pipefail

# Spotify Ads API pre-tool hook (PreToolUse on Claude/Codex/Antigravity)
#
# Two jobs, both before any command that targets the Spotify Ads API:
#   1. Auto-refresh expired OAuth tokens.
#   2. Enforce telemetry attribution, so per-skill usage and error-rate
#      reporting is not blind to raw curl calls made outside a skill's api()
#      wrapper. Logic lives in lib/attribution.sh.
#
# Claude/Codex payload: .tool_input.command; supports command rewriting, and
#   carries .transcript_path (nullable on Codex).
# Antigravity payload: .toolCall.args.CommandLine; decision allow/deny only (no
#   rewrite), so attribution there is a nudge rather than an injection.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PLUGIN_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"

if [ -n "${CODEX_PLUGIN_ROOT:-}" ] && [ -d "${CODEX_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CODEX_PLUGIN_ROOT"
elif [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -d "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  PLUGIN_ROOT="$CLAUDE_PLUGIN_ROOT"
fi

# Read all stdin (hook input JSON)
input=$(cat)

# Fast path: skip anything that cannot be a Spotify Ads API call. The literal
# host covers most calls; $BASE_URL covers the variable form used by the assets
# and audiences upload flows. Precise matching happens on the extracted command.
case "$input" in
  *api-partner.spotify.com*) ;;
  *BASE_URL*) ;;
  *) exit 0 ;;
esac

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
# Path to the session transcript, for best-effort skill inference.
# Claude/Codex: .transcript_path (Codex may send null). Antigravity: .transcriptPath.
transcript_path=$(printf '%s' "$input" | jq -r '
  .transcript_path //
  .transcriptPath //
  ""')

# Does this command actually target the Spotify Ads API? The literal host is
# unambiguous. $BASE_URL is not, since any project may define it, so require
# Spotify-specific corroboration before claiming the command as ours.
is_spotify_api_call() {
  case "$1" in
    *api-partner.spotify.com*) return 0 ;;
  esac
  case "$1" in
    *BASE_URL*)
      case "$1" in
        *X-Spotify-Ads-*|*SDK_HEADER*|*SKILL_HEADER*|*ad_accounts*) return 0 ;;
      esac
      ;;
  esac
  return 1
}

if [[ -z "$command" ]] || ! is_spotify_api_call "$command"; then
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
      system_message="Spotify API token may be expired but no refresh credentials are configured. Run the configure skill (/spotify-ads-api:configure on Claude/Codex, /configure on Antigravity) to set up OAuth."
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

# --- Skill and SDK attribution ---
#
# Sourced here rather than at the top so an unrelated Bash call still exits on
# the fast path without paying for it. This file owns the single command
# rewrite, which now carries both the refreshed token and the attribution
# headers; see lib/attribution.sh for why attribution must not be its own hook.
#
# SPOTIFY_ADS_ATTRIBUTION_LIB overrides the path so a deliberately broken copy
# can be tested without editing the installed one.
ATTRIBUTION_LIB="${SPOTIFY_ADS_ATTRIBUTION_LIB:-$SCRIPT_DIR/lib/attribution.sh}"

if [ -f "$ATTRIBUTION_LIB" ]; then
  # shellcheck source=lib/attribution.sh
  . "$ATTRIBUTION_LIB"

  apply_attribution "$command" "$modified_command" "$PLATFORM" "$transcript_path"
  modified_command="$ATTRIBUTION_COMMAND"

  if [ -n "$ATTRIBUTION_NOTE" ]; then
    system_message="${system_message:+$system_message }$ATTRIBUTION_NOTE"
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
