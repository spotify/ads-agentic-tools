#!/bin/bash
# Tests for scripts/check-request.py and its use in scripts/api-request.sh.
# Run: bash tests/test-check-request.sh
#
# Uses tests/fixtures/openapi-mini.yaml and eval replay mode, so nothing here
# touches the network or a real ad account.

set -uo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
CHECK="$REPO_ROOT/scripts/check-request.py"
API="$REPO_ROOT/scripts/api-request.sh"
SPEC="$SCRIPT_DIR/fixtures/openapi-mini.yaml"

PASS=0
FAIL=0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

PYTHON=""
for candidate in python3 python py; do
  if command -v "$candidate" >/dev/null 2>&1; then PYTHON="$candidate"; break; fi
done
if [ -z "$PYTHON" ]; then
  echo "SKIP: Python 3 is not available"
  exit 0
fi

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; echo "    output: $2"; FAIL=$((FAIL + 1)); }

# expect_check <label> <expected exit> <expected substring> <METHOD> <path> [body]
expect_check() {
  local label="$1" want_status="$2" want_text="$3" output status
  shift 3
  output=$("$PYTHON" -I "$CHECK" "$SPEC" "$@" 2>&1)
  status=$?
  if [ "$status" -eq "$want_status" ] && [[ "$output" == *"$want_text"* ]]; then
    pass "$label"
  else
    fail "$label (exit $status, wanted $want_status and '$want_text')" "$output"
  fi
}

ACCOUNT="ad_accounts/{ad_account_id}"

echo "=== Valid requests pass ==="
expect_check "list with known filters" 0 "OK" GET "$ACCOUNT/ad_sets?campaign_ids=abc&statuses=ACTIVE&delivery=OFF"
expect_check "repeated array parameter" 0 "OK" GET "$ACCOUNT/ad_sets?statuses=ACTIVE&statuses=ARCHIVED"
expect_check "create with required fields" 0 "OK" POST "$ACCOUNT/ad_sets" '{"name":"a","bid_strategy":"MAX_BID","targets":{"platforms":["IOS"],"age_ranges":[{"min":18,"max":34}]}}'
expect_check "PATCH may omit required fields" 0 "OK" PATCH "$ACCOUNT/ad_sets/abc" '{"delivery":"OFF"}'
expect_check "open object accepts any keys" 0 "OK" POST "$ACCOUNT/ad_sets" '{"name":"a","bid_strategy":"AUTOBID","metadata":{"anything":1}}'
expect_check "literal path beats placeholder" 0 "OK" GET "$ACCOUNT/ad_sets/summary"
expect_check "undocumented catalog endpoint passes" 0 "OK" GET "ad_product_catalog"

echo ""
echo "=== Invented paths and methods are rejected ==="
expect_check "nested route" 1 "Closest: /ad_accounts/{ad_account_id}/ad_sets" GET "$ACCOUNT/campaigns/abc/ad_sets"
expect_check "PUT" 1 "PUT is not defined for /ad_accounts/{ad_account_id}/campaigns/{campaign_id}. Allowed: GET, PATCH" PUT "$ACCOUNT/campaigns/abc" '{"name":"x"}'

echo ""
echo "=== Query parameters ==="
expect_check "unknown parameter" 1 "query parameter 'is_paused' is not defined" GET "$ACCOUNT/ad_sets?is_paused=true"
expect_check "enum value not allowed" 1 "query statuses=PAUSED is not one of" GET "$ACCOUNT/ad_sets?statuses=PAUSED"
expect_check "enum error lists the other parameters" 1 "Other query parameters for GET /ad_accounts/{ad_account_id}/ad_sets: campaign_ids, delivery" GET "$ACCOUNT/ad_sets?statuses=PAUSED"
expect_check "comma-joined array" 1 "Repeat the parameter instead: statuses=ACTIVE&statuses=ARCHIVED" GET "$ACCOUNT/ad_sets?statuses=ACTIVE,ARCHIVED"

echo ""
echo "=== Request bodies ==="
expect_check "missing required field from allOf" 1 "required body field 'bid_strategy' is missing" POST "$ACCOUNT/ad_sets" '{"name":"a"}'
expect_check "unknown field" 1 "body field 'status' is not defined" PATCH "$ACCOUNT/ad_sets/abc" '{"status":"PAUSED"}'
expect_check "unknown nested field" 1 "body field 'targets.dma_ids' is not defined" PATCH "$ACCOUNT/ad_sets/abc" '{"targets":{"dma_ids":["1"]}}'
expect_check "enum inside array" 1 "is not one of ['ANDROID', 'DESKTOP', 'IOS']" PATCH "$ACCOUNT/ad_sets/abc" '{"targets":{"platforms":["MOBILE"]}}'
expect_check "object where string expected" 1 "bid_strategy must be string, got dict" PATCH "$ACCOUNT/ad_sets/abc" '{"bid_strategy":{"type":"MAX_BID"}}'
expect_check "boolean is not an integer" 1 "must be integer, got bool" PATCH "$ACCOUNT/ad_sets/abc" '{"targets":{"age_ranges":[{"min":true}]}}'
expect_check "invalid JSON" 1 "body is not valid JSON" PATCH "$ACCOUNT/ad_sets/abc" '{"name":'

echo ""
echo "=== Usage errors exit 2 ==="
SPEC="$WORK/missing.yaml"
expect_check "missing spec file" 2 "could not read OpenAPI document" GET "$ACCOUNT/ad_sets"
SPEC="$SCRIPT_DIR/fixtures/openapi-mini.yaml"
expect_check "wrong argument count" 2 "Usage" GET

echo ""
echo "=== api-request.sh runs the check before sending ==="
PROJECT="$WORK/project"
FIXTURES="$PROJECT/fixtures"
mkdir -p "$PROJECT/.claude" "$FIXTURES"
printf -- '---\naccess_token: "TEST_TOKEN"\nad_account_id: "acct"\nauto_execute: false\n---\n' > "$PROJECT/.claude/spotify-ads-api.local.md"
cp "$SPEC" "$FIXTURES/openapi.yaml"
printf '200\n{"ad_sets":[]}\n' > "$FIXTURES/GET__ad_accounts__{ad_account_id}__ad_sets.http"

run_api() {
  env -u CODEX_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_ROOT -u SPOTIFY_ADS_OPENAPI_FILE \
    CLAUDE_PROJECT_DIR="$PROJECT" TMPDIR="$WORK" EVAL_ADS_API_FIXTURES="$FIXTURES" \
    EVAL_ADS_API_LOG="$WORK/requests.log" "$@" bash "$API" test-skill GET "ad_accounts/{ad_account_id}/ad_sets?statuses=PAUSED"
}

output=$(run_api 2>&1); status=$?
if [ "$status" -eq 3 ] && [[ "$output" == *"NOT SENT"* ]] && [[ "$output" == *"statuses=PAUSED is not one of"* ]]; then
  pass "invalid request is blocked with exit 3"
else
  fail "invalid request is blocked with exit 3 (exit $status)" "$output"
fi
if grep -q '^NOT_SENT GET ' "$WORK/requests.log" 2>/dev/null && ! grep -qv '^NOT_SENT ' "$WORK/requests.log"; then
  pass "blocked request is logged as NOT_SENT and never reaches the transport"
else
  fail "blocked request is logged as NOT_SENT and never reaches the transport" "$(cat "$WORK/requests.log" 2>/dev/null)"
fi

output=$(env -u CODEX_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_ROOT -u SPOTIFY_ADS_OPENAPI_FILE \
  CLAUDE_PROJECT_DIR="$PROJECT" TMPDIR="$WORK" EVAL_ADS_API_FIXTURES="$FIXTURES" EVAL_ADS_API_LOG="$WORK/requests.log" \
  bash "$API" test-skill GET "ad_accounts/{ad_account_id}/ad_sets?delivery=OFF" 2>&1); status=$?
if [ "$status" -eq 0 ] && [[ "$output" == *"HTTP_STATUS:200"* ]]; then
  pass "valid request is sent"
else
  fail "valid request is sent (exit $status)" "$output"
fi

printf 'not a spec\n' > "$FIXTURES/openapi.yaml"
output=$(run_api 2>&1); status=$?
if [ "$status" -eq 0 ] && [[ "$output" == *"WARNING"* ]]; then
  pass "replay mode checks against the current snapshot and fails open on a bad one"
else
  fail "replay mode checks against the current snapshot and fails open on a bad one (exit $status)" "$output"
fi
cp "$SPEC" "$FIXTURES/openapi.yaml"

output=$(run_api SPOTIFY_ADS_SKIP_SPEC_CHECK=1 2>&1); status=$?
if [ "$status" -eq 0 ] && [[ "$output" == *"HTTP_STATUS:200"* ]]; then
  pass "SPOTIFY_ADS_SKIP_SPEC_CHECK=1 skips the check"
else
  fail "SPOTIFY_ADS_SKIP_SPEC_CHECK=1 skips the check (exit $status)" "$output"
fi

output=$(run_api SPOTIFY_ADS_OPENAPI_FILE="$WORK/missing.yaml" 2>&1); status=$?
if [ "$status" -eq 0 ] && [[ "$output" == *"WARNING: request not checked"* ]] && [[ "$output" == *"HTTP_STATUS:200"* ]]; then
  pass "missing document sends unchecked with a warning"
else
  fail "missing document sends unchecked with a warning (exit $status)" "$output"
fi

echo ""
echo "=== Parser matches the real document (when Ruby is available) ==="
REAL_SPEC="$WORK/real.yaml"
if command -v ruby >/dev/null 2>&1 && "$REPO_ROOT/scripts/fetch-openapi-schema.sh" "$REAL_SPEC" >/dev/null 2>&1; then
  ruby -ryaml -rjson -e 'puts JSON.generate(YAML.load_file(ARGV[0]))' "$REAL_SPEC" > "$WORK/real.json"
  output=$("$PYTHON" -I - "$CHECK" "$REAL_SPEC" "$WORK/real.json" <<'PY' 2>&1
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("check", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ours = module.load_yaml(open(sys.argv[2], encoding="utf-8").read())
theirs = json.load(open(sys.argv[3], encoding="utf-8"))

def same(a, b):
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(same(a[k], b[k]) for k in a)
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(same(x, y) for x, y in zip(a, b))
    if isinstance(a, str) and isinstance(b, str):
        return a.split() == b.split()  # block scalars may differ only in whitespace
    return a == b

print("same" if same(ours, theirs) else "different")
PY
)
  if [ "$output" = "same" ]; then
    pass "parsed document matches Ruby's YAML loader"
  else
    fail "parsed document matches Ruby's YAML loader" "$output"
  fi
else
  echo "  SKIP: Ruby or the network is unavailable"
fi

echo ""
echo "Passed: $PASS  Failed: $FAIL"
[ "$FAIL" -eq 0 ]
