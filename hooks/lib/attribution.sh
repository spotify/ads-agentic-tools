#!/bin/bash
# Spotify Ads API telemetry attribution.
#
# scripts/api-request.sh sets X-Spotify-Ads-Skill and X-Spotify-Ads-Sdk
# deterministically, but agents sometimes hand-write curl instead. Those calls
# are indistinguishable from pre-1.7.0 traffic in reporting, so this recovers
# whatever attribution is available.
#
# The SDK header is deterministic: the platform and plugin version are known
# exactly. The skill name can only be inferred, so an inferred value carries an
# "-inferred" suffix, keeping best-effort attribution separable from the
# wrapper's exact value downstream.
#
# This is sourced by hooks/check-token.sh, which owns the single command
# rewrite. Attribution must never be registered as a hook of its own: matching
# PreToolUse hooks run in parallel against the original input and the last
# updatedInput to finish wins, so a second rewriting hook would race the token
# refresh and silently drop one of the two edits.
#
# Interface
#   apply_attribution <original_command> <current_command> <platform> <transcript>
#     Reads   PLUGIN_ROOT, for the skills/ lookup and scripts/api-request.sh
#     Sets    ATTRIBUTION_COMMAND  current_command, rewritten when needed
#             ATTRIBUTION_NOTE     message for the agent, empty when there is none
#     Never fails the caller. When it cannot rewrite, it degrades to a note.

INFERRED_SUFFIX="-inferred"
LOOKBACK_LINES="${SPOTIFY_ADS_SKILL_LOOKBACK_LINES:-300}"

# A command counts as attributed if it names the header, references the shell
# variable holding it, or delegates to the wrapper that always sets it.
has_skill_attribution() {
  case "$1" in
    *X-Spotify-Ads-Skill*|*SKILL_HEADER*|*api-request.sh*) return 0 ;;
  esac
  return 1
}

has_sdk_attribution() {
  case "$1" in
    *X-Spotify-Ads-Sdk*|*SDK_HEADER*|*api-request.sh*) return 0 ;;
  esac
  return 1
}

# A single character is a shell word boundary if it cannot be part of a command
# name. Empty means start or end of string, which also counts.
is_word_boundary() {
  [ -z "$1" ] && return 0
  case "$1" in
    [A-Za-z0-9_.-]) return 1 ;;
    *) return 0 ;;
  esac
}

# Insert extra arguments immediately after every `curl` command word. curl
# accepts options in any position, so this is safe wherever curl appears. The
# boundary checks leave `curl-config`, `mycurl`, and `curlimages` untouched, and
# the quote parity check skips a `curl` sitting inside a single-quoted string,
# which is how every request body in this plugin is written (-d '{"..."}').
# A `curl` inside a double-quoted string is not detected; treat that as a known
# limitation rather than tokenizing shell syntax in bash.
# Returns 1 when the command holds no curl invocation to rewrite.
inject_curl_args() {
  local extra="$2"
  local out="" rest="$1" before after prev next injected=1 quoted=0 quotes

  while :; do
    case "$rest" in
      *curl*) ;;
      *) break ;;
    esac

    before="${rest%%curl*}"
    after="${rest#*curl}"

    # An odd running count of single quotes means this position is inside a
    # single-quoted string, so it is data rather than a command.
    quotes=$(printf '%s' "$before" | tr -cd "'" | wc -c | tr -d ' ')
    quoted=$(( (quoted + quotes) % 2 ))

    prev=""
    [ -n "$before" ] && prev="${before#"${before%?}"}"
    next=""
    [ -n "$after" ] && next="${after%"${after#?}"}"

    if [ "$quoted" -eq 0 ] && is_word_boundary "$prev" && is_word_boundary "$next"; then
      out="${out}${before}curl ${extra}"
      injected=0
    else
      out="${out}${before}curl"
    fi
    rest="$after"
  done

  printf '%s' "${out}${rest}"
  return $injected
}

# Only accept names that map to a real skill in this plugin, so a bad parse can
# never push a junk value into the reporting dimension.
is_known_skill() {
  local name="$1"
  [ -n "$name" ] || return 1
  case "$name" in
    *[!a-z0-9-]*) return 1 ;;
  esac
  [ "$name" = "spotify-ads-request-builder" ] && return 0
  [ -f "$PLUGIN_ROOT/skills/$name/SKILL.md" ]
}

# Best-effort recovery of the active skill from recent transcript lines. Scans
# newest-first and takes the first candidate naming a real skill, so recency
# beats pattern strength. Deliberately plain-text: the same patterns work on
# Claude, Codex, and Antigravity transcripts without encoding any one
# platform's JSON schema.
infer_skill() {
  local transcript="$1" line name pattern
  [ -n "$transcript" ] && [ -f "$transcript" ] || return 1

  while IFS= read -r line; do
    for pattern in \
      's/.*X-Spotify-Ads-Skill: *\([a-z0-9][a-z0-9-]*\).*/\1/p' \
      's/.*api-request\.sh[^a-z0-9]\{1,\}\([a-z0-9][a-z0-9-]*\).*/\1/p' \
      's/.*spotify-ads-api:\([a-z0-9][a-z0-9-]*\).*/\1/p' \
      's/.*\(spotify-ads-request-builder\).*/\1/p'
    do
      name=$(printf '%s' "$line" | sed -n "$pattern")
      name="${name%$INFERRED_SUFFIX}"
      if is_known_skill "$name"; then
        printf '%s' "$name"
        return 0
      fi
    done
  done < <(tail -n "$LOOKBACK_LINES" "$transcript" 2>/dev/null \
             | awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }')

  return 1
}

# Ask the request wrapper for the SDK header so the injected value cannot drift
# from what skills send. This needs a settings file; without one the API call
# would fail regardless, so skipping injection there costs nothing.
sdk_header_value() {
  local env_out
  env_out=$("$PLUGIN_ROOT/scripts/api-request.sh" --env 2>/dev/null) || return 1
  printf '%s' "$env_out" | sed -n "s/^SDK_HEADER='\(.*\)'\$/\1/p"
}

apply_attribution() {
  local original="$1" current="$2" platform="$3" transcript="$4"
  local inject_args="" skill_injected="" sdk_value inferred_skill rewritten

  ATTRIBUTION_COMMAND="$current"
  ATTRIBUTION_NOTE=""

  if ! has_sdk_attribution "$original"; then
    sdk_value=$(sdk_header_value) || sdk_value=""
    if [ -n "$sdk_value" ]; then
      inject_args="-H '$sdk_value'"
    fi
  fi

  if ! has_skill_attribution "$original"; then
    # Antigravity cannot rewrite the command, so inference there would be unused.
    if [ "$platform" = "antigravity" ]; then
      inferred_skill=""
    else
      inferred_skill=$(infer_skill "$transcript") || inferred_skill=""
    fi

    if [ -n "$inferred_skill" ]; then
      skill_injected="${inferred_skill}${INFERRED_SUFFIX}"
      inject_args="${inject_args:+$inject_args }-H 'X-Spotify-Ads-Skill: ${skill_injected}'"
    fi
  fi

  if [ -n "$inject_args" ] && [ "$platform" != "antigravity" ]; then
    if rewritten=$(inject_curl_args "$current" "$inject_args"); then
      ATTRIBUTION_COMMAND="$rewritten"
    else
      # No curl to rewrite (a Python client, say). Fall through to the nudge.
      skill_injected=""
    fi
  fi

  if [ -n "$skill_injected" ]; then
    ATTRIBUTION_NOTE="Spotify Ads API call was missing X-Spotify-Ads-Skill; the hook added \"${skill_injected}\", inferred from recent session context. Prefer the skill's api() helper, which sets attribution headers deterministically."
  elif ! has_skill_attribution "$original"; then
    ATTRIBUTION_NOTE="Spotify Ads API call has no X-Spotify-Ads-Skill header, so reporting cannot attribute it to a skill. Use the skill's api() helper -- api() { \"\$PLUGIN_ROOT/scripts/api-request.sh\" <skill-name> \"\$@\"; } -- instead of raw curl."
  fi
}
