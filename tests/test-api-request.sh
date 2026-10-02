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
echo "=== {ad_account_id} substitution ==="

# Stub curl on PATH so the real request is captured instead of sent.
mkdir -p "$TMPDIR/bin"
printf '#!/bin/bash\nfor a in "$@"; do printf "%%s\\n" "$a"; done\n' > "$TMPDIR/bin/curl"
chmod +x "$TMPDIR/bin/curl"
run_request() {
  env -u CODEX_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_ROOT \
    PATH="$TMPDIR/bin:$PATH" CLAUDE_PROJECT_DIR="$PROJECT" bash "$API" "$@"
}
out=$(run_request estimates POST "estimates/audience" '{"ad_account_id":"{ad_account_id}","x":1}')
assert_eq "placeholder in body is replaced" \
  "1" "$(printf '%s\n' "$out" | grep -cx '{"ad_account_id":"test_account","x":1}')"
out=$(run_request campaigns GET "ad_accounts/{ad_account_id}/campaigns")
assert_eq "placeholder in path is replaced" \
  "1" "$(printf '%s\n' "$out" | grep -c '/ad_accounts/test_account/campaigns$')"

echo "=== no settings file ==="

mv "$PROJECT/.claude/spotify-ads-api.local.md" "$TMPDIR/settings.bak"
run_env campaigns --env >/dev/null 2>&1
assert_eq "exits non-zero without a settings file" "1" "$?"
mv "$TMPDIR/settings.bak" "$PROJECT/.claude/spotify-ads-api.local.md"

echo "=== eval replay mode ==="

write_settings TEST_TOKEN "00000000-0000-4000-8000-000000000001"
FIXTURES="$PROJECT/.ads-api"
mkdir -p "$FIXTURES"
printf '201\n{"id":"c1"}\n' > "$FIXTURES/POST__ad_accounts__{ad_account_id}__drafts__campaigns.http"
printf '200\n{"call":1}\n' > "$FIXTURES/GET__ad_accounts__{ad_account_id}__drafts__campaigns__{id}.http"
printf '200\n{"call":2}\n' > "$FIXTURES/GET__ad_accounts__{ad_account_id}__drafts__campaigns__{id}.2.http"

run_replay() {
  env -u CODEX_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_ROOT \
    CLAUDE_PROJECT_DIR="$PROJECT" EVAL_ADS_API_FIXTURES=.ads-api bash "$API" "$@"
}
status_of() { printf '%s' "$1" | sed -n 's/^HTTP_STATUS://p'; }

out=$(run_replay drafts POST "ad_accounts/{ad_account_id}/drafts/campaigns" '{"name":"x"}')
assert_eq "replay returns the fixture status" "201" "$(status_of "$out")"
assert_eq "replay returns the fixture body" '{"id":"c1"}' "$(printf '%s' "$out" | head -1)"

out=$(run_replay drafts GET "ad_accounts/00000000-0000-4000-8000-000000000001/drafts/campaigns/9b3e4c6a-3d9f-4e5a-9c4b-2f7a0d9e8c33?fields=all")
assert_eq "literal account ID, UUID, and query normalize to the same key" '{"call":1}' "$(printf '%s' "$out" | head -1)"
out=$(run_replay drafts GET "ad_accounts/{ad_account_id}/drafts/campaigns/9b3e4c6a-3d9f-4e5a-9c4b-2f7a0d9e8c33")
assert_eq "a numbered fixture answers the second call" '{"call":2}' "$(printf '%s' "$out" | head -1)"

out=$(run_replay drafts DELETE "ad_accounts/{ad_account_id}/drafts/campaigns/c1")
assert_eq "a missing fixture answers 404" "404" "$(status_of "$out")"

printf '200\n{"validated":true}\n' > "$FIXTURES/POST__ad_accounts__{ad_account_id}__drafts__campaigns__{id}.match-VALIDATE.http"
printf '200\n{"published":true}\n' > "$FIXTURES/POST__ad_accounts__{ad_account_id}__drafts__campaigns__{id}.match-PUBLISH.http"
out=$(run_replay drafts POST "ad_accounts/{ad_account_id}/drafts/campaigns/9b3e4c6a-3d9f-4e5a-9c4b-2f7a0d9e8c33" '{"action":"PUBLISH","draft_hierarchy_version":2}')
assert_eq "a match fixture answers by body content" '{"published":true}' "$(printf '%s' "$out" | head -1)"
out=$(run_replay drafts POST "ad_accounts/{ad_account_id}/drafts/campaigns/9b3e4c6a-3d9f-4e5a-9c4b-2f7a0d9e8c33" '{"action":"VALIDATE","draft_hierarchy_version":2}')
assert_eq "a different body picks a different match fixture" '{"validated":true}' "$(printf '%s' "$out" | head -1)"

assert_eq "every request is logged" "6" "$(wc -l < "$PROJECT/.claude/.api-requests.log" | tr -d ' ')"
assert_eq "the log records the body" "1" \
  "$(grep -c '^POST__ad_accounts__{ad_account_id}__drafts__campaigns .* {"name":"x"}$' "$PROJECT/.claude/.api-requests.log")"

echo "=== eval record mode ==="

STUB_BIN="$TMPDIR/bin"
mkdir -p "$STUB_BIN"
printf '#!/bin/bash\nprintf %s\n' "'{\"campaigns\":[]}\nHTTP_STATUS:200'" > "$STUB_BIN/curl"
chmod +x "$STUB_BIN/curl"
run_record() {
  env -u CODEX_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_ROOT PATH="$STUB_BIN:$PATH" \
    CLAUDE_PROJECT_DIR="$PROJECT" EVAL_ADS_API_RECORD=recorded bash "$API" "$@"
}

run_record campaigns POST "ad_accounts/{ad_account_id}/campaigns" '{"name":"x"}' >/dev/null 2>&1
assert_eq "recording refuses writes" "1" "$?"
assert_eq "a refused write records nothing" "0" "$(ls "$PROJECT/recorded" 2>/dev/null | wc -l | tr -d ' ')"

out=$(run_record campaigns GET "ad_accounts/{ad_account_id}/campaigns?limit=50")
assert_eq "recording passes the response through" "HTTP_STATUS:200" "$(printf '%s' "$out" | tail -1)"
assert_eq "recording saves status and body under the fixture key" $'200\n{"campaigns":[]}' \
  "$(cat "$PROJECT/recorded/GET__ad_accounts__{ad_account_id}__campaigns.http")"

echo
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
