#!/bin/bash
# Unit tests for scripts/api-request.sh --env output.
# Run: bash tests/test-api-request.sh
#
# --env is cheap to drive end to end (it needs only a settings file and makes no
# network calls), so these run the real script rather than copying its logic.

set -uo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
API="$REPO_ROOT/scripts/api-request.sh"

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

PROJECT="$TMPDIR/project"
mkdir -p "$PROJECT/.claude"
write_settings() {
  printf -- '---\naccess_token: "%s"\nad_account_id: "%s"\nauto_execute: false\ntoken_expires_at: "2099-01-01T00:00:00Z"\n---\n' \
    "${1:-TEST_TOKEN}" "${2:-test_account}" > "$PROJECT/.claude/spotify-ads-api.local.md"
}
write_settings

# Run api-request.sh with a clean environment pinned at the fixture project.
run_env() {
  env -u CODEX_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_ROOT \
    CLAUDE_PROJECT_DIR="$PROJECT" bash "$API" "$@"
}

# Evaluate --env output in a subshell and echo one variable back out.
eval_and_get() {
  local var="$1"; shift
  env -u CODEX_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_ROOT \
    CLAUDE_PROJECT_DIR="$PROJECT" bash -c '
      eval $(bash "$1" "${@:3}")
      eval "printf %s \"\${$2:-<UNSET>}\""
    ' _ "$API" "$var" "$@"
}

echo "=== --env is eval-safe ==="

# The regression this guards: unquoted output word-splits on the space inside
# SDK_HEADER, so every line becomes a prefix assignment to a bogus command and
# eval silently sets nothing at all.
assert_eq "TOKEN survives eval"          "TEST_TOKEN"   "$(eval_and_get TOKEN campaigns --env)"
assert_eq "AD_ACCOUNT_ID survives eval"  "test_account" "$(eval_and_get AD_ACCOUNT_ID campaigns --env)"
assert_eq "AUTO_EXECUTE survives eval"   "false"        "$(eval_and_get AUTO_EXECUTE campaigns --env)"
assert_eq "BASE_URL survives eval" \
  "https://api-partner.spotify.com/ads/v3" "$(eval_and_get BASE_URL campaigns --env)"

version=$(grep '"version"' "$REPO_ROOT/.claude-plugin/plugin.json" | head -1 | sed 's/.*"version" *: *"\([^"]*\)".*/\1/')
assert_eq "SDK_HEADER survives eval despite its space" \
  "X-Spotify-Ads-Sdk: claude-code-plugin/$version" "$(eval_and_get SDK_HEADER campaigns --env)"
assert_eq "PLUGIN_VERSION survives eval" "$version" "$(eval_and_get PLUGIN_VERSION campaigns --env)"

echo "=== every emitted line is quoted ==="

unquoted=$(run_env campaigns --env | grep -vc "^[A-Z_]*='.*'$")
assert_eq "no unquoted assignment lines" "0" "$unquoted"

echo "=== SKILL_HEADER ==="

assert_eq "SKILL_HEADER is set from the skill argument" \
  "X-Spotify-Ads-Skill: assets" "$(eval_and_get SKILL_HEADER assets --env)"
assert_eq "SKILL_HEADER reflects a different skill" \
  "X-Spotify-Ads-Skill: drafts" "$(eval_and_get SKILL_HEADER drafts --env)"
assert_eq "SKILL_HEADER is omitted when no skill is given" \
  "<UNSET>" "$(eval_and_get SKILL_HEADER --env)"
assert_eq "bare --env still emits SDK_HEADER" \
  "X-Spotify-Ads-Sdk: claude-code-plugin/$version" "$(eval_and_get SDK_HEADER --env)"

echo "=== values containing shell metacharacters ==="

write_settings 'tok en' 'acct'
assert_eq "token containing a space survives eval" "tok en" "$(eval_and_get TOKEN campaigns --env)"

write_settings 'a|b&c' 'acct'
assert_eq "token containing pipe and ampersand survives eval" "a|b&c" "$(eval_and_get TOKEN campaigns --env)"

write_settings 'a$(echo pwned)b' 'acct'
assert_eq "command substitution in a token is not executed" \
  'a$(echo pwned)b' "$(eval_and_get TOKEN campaigns --env)"

write_settings '`echo pwned`' 'acct'
assert_eq "backticks in a token are not executed" \
  '`echo pwned`' "$(eval_and_get TOKEN campaigns --env)"

write_settings
echo "=== no settings file ==="

mv "$PROJECT/.claude/spotify-ads-api.local.md" "$TMPDIR/settings.bak"
run_env campaigns --env >/dev/null 2>&1
assert_eq "exits non-zero without a settings file" "1" "$?"
mv "$TMPDIR/settings.bak" "$PROJECT/.claude/spotify-ads-api.local.md"

echo
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
