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
# Summary
# ============================================================

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
