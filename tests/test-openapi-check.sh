#!/bin/bash
# Regression tests for live OpenAPI checks in scripts/api-request.sh.
# Run: bash tests/test-openapi-check.sh

set -uo pipefail

PASS=0
FAIL=0
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FAKE_BIN="$TEST_TMPDIR/bin"
PROJECT_DIR="$TEST_TMPDIR/project"
CURL_LOG="$TEST_TMPDIR/curl.log"
SCHEMA_FIXTURE="$TEST_TMPDIR/api.yaml"

mkdir -p "$FAKE_BIN" "$PROJECT_DIR/.codex"

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

assert_contains() {
  local label="$1" expected="$2" actual="$3"

  if printf '%s' "$actual" | grep -Fq "$expected"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    missing: $expected"
    echo "    actual:  $actual"
    FAIL=$((FAIL + 1))
  fi
}

printf '%s\n' \
  '---' \
  'access_token: "test-token"' \
  'ad_account_id: "account-123"' \
  'auto_execute: true' \
  '---' > "$PROJECT_DIR/.codex/spotify-ads-api.local.md"

printf '%s\n' \
  'openapi: 3.0.3' \
  'paths:' \
  '  /ad_accounts/{ad_account_id}/campaigns:' \
  '    get:' \
  '      responses: {}' \
  '  /ad_accounts/{ad_account_id}/campaigns/{campaign_id}:' \
  '    patch:' \
  '      responses: {}' > "$SCHEMA_FIXTURE"

cat > "$FAKE_BIN/curl" <<'MOCK_CURL'
#!/bin/bash
set -uo pipefail

url="${!#}"
printf '%s\n' "$url" >> "$CURL_LOG"

if [ "$url" = "https://developer.spotify.com/reference/ads-api/v3/api.yaml" ]; then
  if [ "${MOCK_SCHEMA_MODE:-success}" = "fail" ]; then
    exit 22
  fi

  destination=""
  previous=""
  for argument in "$@"; do
    if [ "$previous" = "--output" ]; then
      destination="$argument"
      break
    fi
    previous="$argument"
  done

  cp "$SCHEMA_FIXTURE" "$destination"
  exit 0
fi

printf '{"ok":true}\nHTTP_STATUS:200\n'
MOCK_CURL
chmod +x "$FAKE_BIN/curl"

export CURL_LOG SCHEMA_FIXTURE

run_api() {
  PATH="$FAKE_BIN:$PATH" \
    CODEX_PROJECT_DIR="$PROJECT_DIR" \
    CODEX_PLUGIN_ROOT="$REPO_ROOT" \
    "$REPO_ROOT/scripts/api-request.sh" "$@" 2>&1
}

echo "=== documented operation ==="
: > "$CURL_LOG"
output=$(run_api campaigns GET "ad_accounts/{ad_account_id}/campaigns?limit=50")
status=$?
assert_eq "request succeeds" "0" "$status"
assert_contains "API response returned" 'HTTP_STATUS:200' "$output"
assert_eq "schema fetched before API request" \
  $'https://developer.spotify.com/reference/ads-api/v3/api.yaml\nhttps://api-partner.spotify.com/ads/v3/ad_accounts/account-123/campaigns?limit=50' \
  "$(cat "$CURL_LOG")"

echo ""
echo "=== templated path ==="
: > "$CURL_LOG"
output=$(run_api campaigns PATCH "ad_accounts/{ad_account_id}/campaigns/campaign-456" '{"status":"PAUSED"}')
status=$?
assert_eq "concrete resource ID matches OAS template" "0" "$status"
assert_eq "schema and API were both requested" "2" "$(wc -l < "$CURL_LOG" | tr -d ' ')"

echo ""
echo "=== undocumented operation ==="
: > "$CURL_LOG"
output=$(run_api campaigns DELETE "ad_accounts/{ad_account_id}/campaigns/campaign-456")
status=$?
assert_eq "request is rejected" "1" "$status"
assert_contains "rejection identifies missing operation" \
  'DELETE /ad_accounts/account-123/campaigns/campaign-456 is not documented' "$output"
assert_eq "Ads API is not called" \
  'https://developer.spotify.com/reference/ads-api/v3/api.yaml' \
  "$(cat "$CURL_LOG")"

echo ""
echo "=== schema fetch failure ==="
: > "$CURL_LOG"
output=$(MOCK_SCHEMA_MODE=fail run_api campaigns GET "ad_accounts/{ad_account_id}/campaigns")
status=$?
assert_eq "request fails closed" "1" "$status"
assert_contains "failure explains no API request was sent" 'No API request was sent.' "$output"
assert_eq "only schema fetch was attempted" \
  'https://developer.spotify.com/reference/ads-api/v3/api.yaml' \
  "$(cat "$CURL_LOG")"

echo ""
echo "=== static schema removal ==="
if [ ! -e "$REPO_ROOT/skills/api-reference/references/external-v3.yaml" ]; then
  echo "  PASS: bundled schema is absent"
  PASS=$((PASS + 1))
else
  echo "  FAIL: bundled schema still exists"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
