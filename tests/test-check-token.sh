#!/bin/bash
# Unit tests for hooks/check-token.sh functions.
# Run: bash tests/test-check-token.sh

set -uo pipefail

PASS=0
FAIL=0
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    FAIL=$((FAIL + 1))
  fi
}

# ============================================================
# update_setting (awk-based YAML replacement)
# ============================================================

update_setting() {
  local key="$1" val="$2" file="$3"
  local tmp="${file}.tmp.$$"
  AWK_KEY="$key" AWK_VAL="$val" awk '
    BEGIN { k=ENVIRON["AWK_KEY"]; v=ENVIRON["AWK_VAL"]; found=0 }
    { if ($0 ~ "^"k": " && !found) { print k": \""v"\""; found=1 } else print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

echo "=== update_setting ==="

f="$TMPDIR/normal.md"
printf 'access_token: "old_token"\nother: "keep"\n' > "$f"
update_setting "access_token" "new_token_abc123" "$f"
assert_eq "normal token" 'access_token: "new_token_abc123"' "$(grep '^access_token:' "$f")"
assert_eq "other key preserved" 'other: "keep"' "$(grep '^other:' "$f")"

f="$TMPDIR/pipe.md"
printf 'access_token: "old"\n' > "$f"
update_setting "access_token" "token|with|pipes" "$f"
assert_eq "pipe in token" 'access_token: "token|with|pipes"' "$(grep '^access_token:' "$f")"

f="$TMPDIR/amp.md"
printf 'access_token: "old"\n' > "$f"
update_setting "access_token" "token&with&amps" "$f"
assert_eq "ampersand in token" 'access_token: "token&with&amps"' "$(grep '^access_token:' "$f")"

f="$TMPDIR/bs.md"
printf 'access_token: "old"\n' > "$f"
update_setting "access_token" 'token\with\backslashes' "$f"
assert_eq "backslash in token" 'access_token: "token\with\backslashes"' "$(grep '^access_token:' "$f")"

f="$TMPDIR/combo.md"
printf 'access_token: "old"\nrefresh_token: "keep_me"\n' > "$f"
update_setting "access_token" 'a|b&c\d' "$f"
assert_eq "combined metacharacters" 'access_token: "a|b&c\d"' "$(grep '^access_token:' "$f")"
assert_eq "refresh_token untouched" 'refresh_token: "keep_me"' "$(grep '^refresh_token:' "$f")"

f="$TMPDIR/dup.md"
printf 'access_token: "first"\naccess_token: "second"\n' > "$f"
update_setting "access_token" "replaced" "$f"
count=$(grep -c '^access_token: "replaced"' "$f")
assert_eq "only first occurrence replaced" "1" "$count"

f="$TMPDIR/multi.md"
printf 'access_token: "aaa"\ntoken_expires_at: "2026-01-01T00:00:00Z"\nrefresh_token: "rrr"\n' > "$f"
update_setting "access_token" "new_access" "$f"
update_setting "token_expires_at" "2026-12-31T23:59:59Z" "$f"
update_setting "refresh_token" "new_refresh" "$f"
assert_eq "sequential update: access_token" 'access_token: "new_access"' "$(grep '^access_token:' "$f")"
assert_eq "sequential update: token_expires_at" 'token_expires_at: "2026-12-31T23:59:59Z"' "$(grep '^token_expires_at:' "$f")"
assert_eq "sequential update: refresh_token" 'refresh_token: "new_refresh"' "$(grep '^refresh_token:' "$f")"

# ============================================================
# Token substitution in command (set -f glob protection)
# ============================================================

echo ""
echo "=== token substitution ==="

do_substitution() {
  local modified_command="$1" access_token="$2" new_token="$3"
  set -f
  modified_command="${modified_command//"$access_token"/$new_token}"
  set +f
  echo "$modified_command"
}

result=$(do_substitution "curl -H 'Bearer abc123' https://api.example.com" "abc123" "xyz789")
assert_eq "normal substitution" "curl -H 'Bearer xyz789' https://api.example.com" "$result"

result=$(do_substitution "curl -H 'Bearer to*ken' https://api.example.com" "to*ken" "new_token")
assert_eq "star in token" "curl -H 'Bearer new_token' https://api.example.com" "$result"

result=$(do_substitution "curl -H 'Bearer to?ken' https://api.example.com" "to?ken" "new_token")
assert_eq "question mark in token" "curl -H 'Bearer new_token' https://api.example.com" "$result"

result=$(do_substitution "curl -H 'Bearer to[k]en' https://api.example.com" "to[k]en" "new_token")
assert_eq "brackets in token" "curl -H 'Bearer new_token' https://api.example.com" "$result"

result=$(do_substitution "curl -H 'Bearer a*b?c[d]' https://api.example.com" 'a*b?c[d]' "safe_token")
assert_eq "combined glob chars" "curl -H 'Bearer safe_token' https://api.example.com" "$result"

# ============================================================
# get_setting (YAML frontmatter parsing)
# ============================================================

echo ""
echo "=== get_setting ==="

SETTINGS_FILE="$TMPDIR/settings.md"

get_setting() {
  grep "^${1}:" "$SETTINGS_FILE" | head -1 | sed "s/^${1}: *//" | tr -d '"' | tr -d "'"
}

printf 'access_token: "my_token_123"\nad_account_id: "acct_456"\nauto_execute: true\n' > "$SETTINGS_FILE"
assert_eq "double-quoted value" "my_token_123" "$(get_setting access_token)"
assert_eq "unquoted value" "true" "$(get_setting auto_execute)"

printf "access_token: 'single_quoted'\n" > "$SETTINGS_FILE"
assert_eq "single-quoted value" "single_quoted" "$(get_setting access_token)"

printf 'access_token: no_quotes_here\n' > "$SETTINGS_FILE"
assert_eq "bare value" "no_quotes_here" "$(get_setting access_token)"

printf 'access_token: "first_token"\naccess_token: "second_token"\n' > "$SETTINGS_FILE"
assert_eq "returns first match" "first_token" "$(get_setting access_token)"

printf 'access_token: "has spaces around"\n' > "$SETTINGS_FILE"
assert_eq "leading space stripped" "has spaces around" "$(get_setting access_token)"

result=$(get_setting "nonexistent_key")
assert_eq "missing key returns empty" "" "$result"

printf 'token_expires_at: "2026-08-07T12:00:00Z"\n' > "$SETTINGS_FILE"
assert_eq "ISO 8601 timestamp" "2026-08-07T12:00:00Z" "$(get_setting token_expires_at)"

# ============================================================
# find_settings_file (platform-priority file discovery)
# ============================================================

echo ""
echo "=== find_settings_file ==="

find_settings_file() {
  local platform="$1" project_dir="$2"
  local order dir candidate

  case "$platform" in
    antigravity) order=".agents .claude .codex" ;;
    claude) order=".claude .codex .agents" ;;
    *)      order=".codex .claude .agents" ;;
  esac

  for dir in $order; do
    candidate="$project_dir/$dir/spotify-ads-api.local.md"
    if [ -f "$candidate" ]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
}

proj="$TMPDIR/proj_claude"
mkdir -p "$proj/.claude" "$proj/.codex" "$proj/.agents"
touch "$proj/.claude/spotify-ads-api.local.md"
touch "$proj/.codex/spotify-ads-api.local.md"
result=$(find_settings_file "claude" "$proj")
assert_eq "claude prefers .claude/" "$proj/.claude/spotify-ads-api.local.md" "$result"

proj="$TMPDIR/proj_codex"
mkdir -p "$proj/.claude" "$proj/.codex"
touch "$proj/.claude/spotify-ads-api.local.md"
touch "$proj/.codex/spotify-ads-api.local.md"
result=$(find_settings_file "codex" "$proj")
assert_eq "codex prefers .codex/" "$proj/.codex/spotify-ads-api.local.md" "$result"

proj="$TMPDIR/proj_antigravity"
mkdir -p "$proj/.agents" "$proj/.claude"
touch "$proj/.agents/spotify-ads-api.local.md"
touch "$proj/.claude/spotify-ads-api.local.md"
result=$(find_settings_file "antigravity" "$proj")
assert_eq "antigravity prefers .agents/" "$proj/.agents/spotify-ads-api.local.md" "$result"

proj="$TMPDIR/proj_fallback"
mkdir -p "$proj/.codex"
touch "$proj/.codex/spotify-ads-api.local.md"
result=$(find_settings_file "claude" "$proj")
assert_eq "claude falls back to .codex/" "$proj/.codex/spotify-ads-api.local.md" "$result"

proj="$TMPDIR/proj_empty"
mkdir -p "$proj"
result=$(find_settings_file "claude" "$proj")
assert_eq "no settings file returns empty" "" "$result"

# ============================================================
# Hook JSON output structure
# ============================================================

echo ""
echo "=== hook JSON output ==="

if command -v jq &>/dev/null; then

  # Antigravity: decision + reason
  json=$(jq -n --arg msg "token refreshed" '{
    "decision": "allow",
    "reason": $msg
  }')
  assert_eq "antigravity has decision" "allow" "$(echo "$json" | jq -r '.decision')"
  assert_eq "antigravity has reason" "token refreshed" "$(echo "$json" | jq -r '.reason')"

  # Claude/Codex: rewrite with system message
  json=$(jq -n --arg cmd "curl -H 'Bearer new' https://api.example.com" --arg msg "token refreshed" '{
    "hookSpecificOutput": {
      "permissionDecision": "allow",
      "updatedInput": {"command": $cmd}
    },
    "systemMessage": $msg
  }')
  assert_eq "claude rewrite has permissionDecision" "allow" "$(echo "$json" | jq -r '.hookSpecificOutput.permissionDecision')"
  assert_eq "claude rewrite has updatedInput.command" "curl -H 'Bearer new' https://api.example.com" "$(echo "$json" | jq -r '.hookSpecificOutput.updatedInput.command')"
  assert_eq "claude rewrite has systemMessage" "token refreshed" "$(echo "$json" | jq -r '.systemMessage')"

  # Claude/Codex: system message only (no rewrite)
  json=$(jq -n --arg msg "no refresh creds" '{"systemMessage": $msg}')
  assert_eq "system-message-only has systemMessage" "no refresh creds" "$(echo "$json" | jq -r '.systemMessage')"
  assert_eq "system-message-only has no hookSpecificOutput" "null" "$(echo "$json" | jq -r '.hookSpecificOutput')"

else
  echo "  SKIP: jq not available, skipping hook JSON output tests"
fi


# ============================================================
# Skill and SDK attribution (hooks/lib/attribution.sh)
# ============================================================
#
# The library is sourced rather than copied, so these unit tests cannot drift
# from the implementation the hook actually loads.

ATTR_REPO_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PLUGIN_ROOT="$ATTR_REPO_ROOT"
# SPOTIFY_ADS_ATTRIBUTION_LIB lets these tests run against a deliberately
# broken copy, to confirm the assertions below can actually fail.
ATTR_LIB="${SPOTIFY_ADS_ATTRIBUTION_LIB:-$ATTR_REPO_ROOT/hooks/lib/attribution.sh}"
# shellcheck source=../hooks/lib/attribution.sh
. "$ATTR_LIB"

yn() { if "$@"; then echo yes; else echo no; fi; }
# A bare `case` inside $( ) does not parse: the pattern's `)` closes the
# substitution. Wrap substring checks in a function instead.
contains() { case "$2" in *"$1"*) echo yes ;; *) echo no ;; esac; }

echo "=== attribution: already-attributed detection ==="

assert_eq "literal skill header counts as attributed" "yes" \
  "$(yn has_skill_attribution 'curl -H "X-Spotify-Ads-Skill: campaigns" https://api-partner.spotify.com/x')"
assert_eq "\$SKILL_HEADER variable counts as attributed" "yes" \
  "$(yn has_skill_attribution 'curl -H "$SKILL_HEADER" "$BASE_URL/ad_accounts/x/assets/1/upload"')"
assert_eq "wrapper delegation counts as attributed" "yes" \
  "$(yn has_skill_attribution 'api-request.sh campaigns GET "ad_accounts/x/campaigns"')"
assert_eq "bare curl is not attributed" "no" \
  "$(yn has_skill_attribution 'curl -s https://api-partner.spotify.com/ads/v3/x')"
assert_eq "literal SDK header counts as attributed" "yes" \
  "$(yn has_sdk_attribution 'curl -H "X-Spotify-Ads-Sdk: claude-code-plugin/1.0.0" https://x')"
assert_eq "\$SDK_HEADER variable counts as attributed" "yes" \
  "$(yn has_sdk_attribution 'curl -H "$SDK_HEADER" https://x')"
assert_eq "bare curl has no SDK attribution" "no" \
  "$(yn has_sdk_attribution 'curl -s https://api-partner.spotify.com/ads/v3/x')"

echo "=== attribution: curl word boundaries ==="

assert_eq "slash is a boundary"        "yes" "$(yn is_word_boundary '/')"
assert_eq "space is a boundary"        "yes" "$(yn is_word_boundary ' ')"
assert_eq "empty is a boundary"        "yes" "$(yn is_word_boundary '')"
assert_eq "letter is not a boundary"   "no"  "$(yn is_word_boundary 'y')"
assert_eq "hyphen is not a boundary"   "no"  "$(yn is_word_boundary '-')"

echo "=== attribution: curl injection ==="

H="-H 'X-Test: v'"
assert_eq "single curl is rewritten" \
  "curl -H 'X-Test: v' -s https://api-partner.spotify.com/x" \
  "$(inject_curl_args 'curl -s https://api-partner.spotify.com/x' "$H")"
assert_eq "curl-config is left alone" \
  "curl-config --version; curl -H 'X-Test: v' -s https://x" \
  "$(inject_curl_args 'curl-config --version; curl -s https://x' "$H")"
assert_eq "mycurl is left alone" \
  "mycurl foo; curl -H 'X-Test: v' -s https://x" \
  "$(inject_curl_args 'mycurl foo; curl -s https://x' "$H")"
assert_eq "absolute path to curl is rewritten" \
  "/usr/bin/curl -H 'X-Test: v' -s https://x" \
  "$(inject_curl_args '/usr/bin/curl -s https://x' "$H")"
assert_eq "both curls in a chain are rewritten" "2" \
  "$(inject_curl_args 'curl -s https://a && curl -s https://b' "$H" | grep -o "X-Test: v" | wc -l | tr -d ' ')"
assert_eq "curl inside a single-quoted body is data, not a command" "1" \
  "$(inject_curl_args "curl -d '{\"n\":\"how to curl\"}' https://x" "$H" | grep -o "X-Test: v" | wc -l | tr -d ' ')"
body_out=$(inject_curl_args "curl -d '{\"n\":\"how to curl\"}' https://x" "$H")
assert_eq "body containing curl is preserved verbatim" "yes" \
  "$(contains '{"n":"how to curl"}' "$body_out")"
inject_curl_args 'python3 -c "urlopen(...)"' "$H" >/dev/null
assert_eq "returns non-zero when there is no curl to rewrite" "1" "$?"

# Word-splitting is the thing that actually matters, so execute the result
# against a stub curl and inspect argv rather than trusting the string shape.
ATTR_STUB="$TMPDIR/stub-bin"
mkdir -p "$ATTR_STUB"
printf '#!/bin/bash\nfor a in "$@"; do printf "ARG[%%s]\\n" "$a"; done\n' > "$ATTR_STUB/curl"
chmod +x "$ATTR_STUB/curl"

multiline=$(printf 'curl -s -X POST \\\n  -H "Authorization: Bearer T" \\\n  -d %s{"name":"x"}%s \\\n  "https://api-partner.spotify.com/ads/v3/x"' "'" "'")
assert_eq "multi-line fixture really has continuations" "3" \
  "$(printf '%s' "$multiline" | grep -c '\\$')"
argv=$(PATH="$ATTR_STUB:$PATH" bash -c "$(inject_curl_args "$multiline" "$H")" 2>&1)
assert_eq "injected header arrives as one argv entry" "yes" \
  "$(contains 'ARG[X-Test: v]' "$argv")"
assert_eq "multi-line rewrite adds no stray single-space argument" "no" \
  "$(contains 'ARG[ ]' "$argv")"
assert_eq "request body survives as one argv entry" "yes" \
  "$(contains 'ARG[{"name":"x"}]' "$argv")"

echo "=== attribution: known-skill validation ==="

assert_eq "a real skill directory is accepted"  "yes" "$(yn is_known_skill campaigns)"
assert_eq "another real skill is accepted"      "yes" "$(yn is_known_skill drafts)"
assert_eq "the request-builder agent is accepted" "yes" "$(yn is_known_skill spotify-ads-request-builder)"
assert_eq "an invented name is rejected"        "no"  "$(yn is_known_skill totally-made-up)"
assert_eq "an empty name is rejected"           "no"  "$(yn is_known_skill '')"
assert_eq "a non-slug name is rejected"         "no"  "$(yn is_known_skill 'Campaigns; rm -rf /')"

echo "=== attribution: skill inference ==="

TR="$TMPDIR/transcript.jsonl"
write_tr() { : > "$TR"; for l in "$@"; do printf '%s\n' "$l" >> "$TR"; done; }

write_tr '{"skill":"spotify-ads-api:campaigns"}'
assert_eq "infers from a Skill invocation" "campaigns" "$(infer_skill "$TR")"

write_tr '{"cmd":"curl -H \"X-Spotify-Ads-Skill: drafts\" https://x"}'
assert_eq "infers from a previous attributed call" "drafts" "$(infer_skill "$TR")"

write_tr '{"cmd":"api() { \"$PLUGIN_ROOT/scripts/api-request.sh\" export \"$@\"; }"}'
assert_eq "infers from a wrapper definition" "export" "$(infer_skill "$TR")"

write_tr '{"skill":"spotify-ads-api:campaigns"}' '{"noise":"chatter"}' '{"skill":"spotify-ads-api:report"}'
assert_eq "recency beats pattern strength" "report" "$(infer_skill "$TR")"

write_tr '{"cmd":"curl -H \"X-Spotify-Ads-Skill: campaigns-inferred\" https://x"}'
assert_eq "an existing -inferred suffix is stripped, not compounded" "campaigns" "$(infer_skill "$TR")"

write_tr '{"cmd":"curl -H \"X-Spotify-Ads-Skill: totally-made-up\" https://x"}'
infer_skill "$TR" >/dev/null
assert_eq "a name that is not a real skill is rejected" "1" "$?"

write_tr '{"noise":"no skill was ever invoked"}'
infer_skill "$TR" >/dev/null
assert_eq "no signal means no inference" "1" "$?"

infer_skill "$TMPDIR/does-not-exist.jsonl" >/dev/null
assert_eq "a missing transcript means no inference" "1" "$?"

write_tr '{"skill":"spotify-ads-api:campaigns"}' '{"noise":"a"}' '{"noise":"b"}'
LOOKBACK_LINES=2 
infer_skill "$TR" >/dev/null
assert_eq "the lookback window excludes older signals" "1" "$?"
LOOKBACK_LINES=300

echo "=== attribution: apply_attribution ==="

ATTR_PROJECT="$TMPDIR/attr-project"
mkdir -p "$ATTR_PROJECT/.claude"
printf -- '---\naccess_token: "T"\nad_account_id: "acct"\nauto_execute: false\ntoken_expires_at: "2099-01-01T00:00:00Z"\n---\n' \
  > "$ATTR_PROJECT/.claude/spotify-ads-api.local.md"
export CLAUDE_PROJECT_DIR="$ATTR_PROJECT"
attr_version=$(grep '"version"' "$ATTR_REPO_ROOT/.claude-plugin/plugin.json" | head -1 | sed 's/.*"version" *: *"\([^"]*\)".*/\1/')

write_tr '{"skill":"spotify-ads-api:campaigns"}'
bare='curl -s https://api-partner.spotify.com/ads/v3/ad_accounts/x/campaigns'

apply_attribution "$bare" "$bare" claude "$TR"
assert_eq "inferred skill header is injected with the -inferred suffix" "yes" \
  "$(contains 'X-Spotify-Ads-Skill: campaigns-inferred' "$ATTRIBUTION_COMMAND")"
assert_eq "deterministic SDK header is injected" "yes" \
  "$(contains "X-Spotify-Ads-Sdk: claude-code-plugin/$attr_version" "$ATTRIBUTION_COMMAND")"
assert_eq "the note names the injected value" "yes" \
  "$(contains 'campaigns-inferred' "$ATTRIBUTION_NOTE")"

apply_attribution "$ATTRIBUTION_COMMAND" "$ATTRIBUTION_COMMAND" claude "$TR"
assert_eq "re-running on its own output changes nothing" "" "$ATTRIBUTION_NOTE"

attributed='curl -H "X-Spotify-Ads-Sdk: x/1" -H "X-Spotify-Ads-Skill: campaigns" https://api-partner.spotify.com/ads/v3/x'
apply_attribution "$attributed" "$attributed" claude "$TR"
assert_eq "an already-attributed command is untouched" "$attributed" "$ATTRIBUTION_COMMAND"
assert_eq "an already-attributed command produces no note" "" "$ATTRIBUTION_NOTE"

apply_attribution "$bare" "$bare" antigravity "$TR"
assert_eq "Antigravity gets no rewrite" "$bare" "$ATTRIBUTION_COMMAND"
assert_eq "Antigravity gets a nudge instead" "yes" \
  "$(contains 'cannot attribute it to a skill' "$ATTRIBUTION_NOTE")"

write_tr '{"noise":"nothing to infer"}'
apply_attribution "$bare" "$bare" claude "$TR"
assert_eq "no inference means no invented skill header" "no" \
  "$(contains 'X-Spotify-Ads-Skill' "$ATTRIBUTION_COMMAND")"
assert_eq "no inference still backfills the SDK header" "yes" \
  "$(contains 'X-Spotify-Ads-Sdk' "$ATTRIBUTION_COMMAND")"
assert_eq "no inference produces the nudge" "yes" \
  "$(contains 'cannot attribute it to a skill' "$ATTRIBUTION_NOTE")"

nocurl='python3 -c "urlopen(1)" # api-partner.spotify.com'
apply_attribution "$nocurl" "$nocurl" claude "$TR"
assert_eq "a command with no curl is not rewritten" "$nocurl" "$ATTRIBUTION_COMMAND"
assert_eq "a command with no curl still gets the nudge" "yes" \
  "$(contains 'api() helper' "$ATTRIBUTION_NOTE")"

unset CLAUDE_PROJECT_DIR

# ============================================================
# Summary
# ============================================================

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
