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

# --- Request-path tests with a stubbed curl ---
#
# The wrapper's request mode is exercised against a curl stub on PATH so the
# 403 allow-list hint can be asserted without network access. The stub writes
# STUB_BODY to the -o file and prints STUB_STATUS, mimicking
# `curl -o <file> -w '%{http_code}'`.

echo "=== request mode: 403 allow-list hint ==="

STUB_DIR="$TMPDIR/stub"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/curl" <<'EOF'
#!/bin/bash
# Minimal curl stub for api-request.sh request-mode tests.
body="${STUB_BODY:-}"
[ -n "$body" ] || body='{}'
while [ $# -gt 0 ]; do
  case "$1" in
    -o) printf '%s' "$body" > "$2"; shift 2 ;;
    -w) shift 2 ;;
    -X|-H|-d) shift 2 ;;
    -s) shift ;;
    --) shift ;;
    *) shift ;;
  esac
done
printf '%s' "${STUB_STATUS:-200}"
EOF
chmod +x "$STUB_DIR/curl"

run_request() {
  env -u CODEX_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_ROOT \
    CLAUDE_PROJECT_DIR="$PROJECT" PATH="$STUB_DIR:$PATH" \
    STUB_STATUS="${1:-}" STUB_BODY="${2:-}" \
    bash "$API" campaigns "$3" "$4" ${5:+"$5"}
}

hint_re='ADS_API_HINT:.*https://adsmanager\.spotify\.com/api-terms'
# Observed shape of the allow-list 403 from a real misconfigured client ID.
allow_body='{"errors":[{"code":"CLIENT_NOT_ALLOWLISTED","message":"Client ID <82898555dd17469aa45036f58d433b04> is not allow-listed"}]}'
# A plain permission denial: no allow-list markers, so no hint may appear.
perm_body='{"errors":[{"code":"FORBIDDEN","message":"User is not authorized to access this ad account"}]}'

get403=$(run_request 403 "$allow_body" GET businesses)
assert_eq "GET 403 keeps the status line" "403" "$(printf '%s' "$get403" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)"
assert_eq "allow-list 403 emits the api-terms hint" "1" "$(printf '%s' "$get403" | grep -cE "$hint_re")"
assert_eq "allow-list 403 still prints the body" "1" "$(printf '%s' "$get403" | grep -c 'CLIENT_NOT_ALLOWLISTED')"

perm403=$(run_request 403 "$perm_body" GET businesses)
assert_eq "permission 403 keeps the status line" "403" "$(printf '%s' "$perm403" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)"
assert_eq "permission 403 emits no allow-list hint" "0" "$(printf '%s' "$perm403" | grep -c 'ADS_API_HINT' || true)"

get200=$(run_request 200 '{}' GET businesses)
assert_eq "GET 200 has no hint" "0" "$(printf '%s' "$get200" | grep -c 'ADS_API_HINT' || true)"
assert_eq "GET 200 keeps the status line" "200" "$(printf '%s' "$get200" | grep -o 'HTTP_STATUS:[0-9]*' | cut -d: -f2)"

# The allow-list marker is method-independent: a write hitting the same
# denial still needs the terms page, unlike edit-permission 403s (perm_body).
post403=$(run_request 403 "$allow_body" POST "ad_accounts/{ad_account_id}/campaigns/dedup-free-path" '{"name":"x"}')
assert_eq "allow-list 403 on POST also emits the hint" "1" "$(printf '%s' "$post403" | grep -cE "$hint_re")"
postperm403=$(run_request 403 "$perm_body" POST "ad_accounts/{ad_account_id}/campaigns/dedup-free-path" '{"name":"x"}')
assert_eq "edit-permission 403 on POST emits no hint" "0" "$(printf '%s' "$postperm403" | grep -c 'ADS_API_HINT' || true)"

get401=$(run_request 401 "$allow_body" GET businesses)
assert_eq "401 emits no allow-list hint" "0" "$(printf '%s' "$get401" | grep -c 'ADS_API_HINT' || true)"

echo
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
