#!/bin/bash
# Regression tests for scripts/openapi_tool.py, scripts/openapi-op.sh, and the
# pre-send spec validation in scripts/api-request.sh.
# Run: bash tests/test-openapi-tool.sh
#
# Offline: uses tests/fixtures/openapi-mini.yaml and a stub curl. Set
# OPENAPI_TOOL_LIVE_SPEC=<path to a downloaded api.yaml> to also check the
# parser against the real published document.

set -uo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
TOOL="$REPO_ROOT/scripts/openapi_tool.py"
OP="$REPO_ROOT/scripts/openapi-op.sh"
API="$REPO_ROOT/scripts/api-request.sh"
FIXTURE="$SCRIPT_DIR/fixtures/openapi-mini.yaml"

PASS=0
FAIL=0
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# Isolate the "current spec" pointer from any real workflow on this machine.
export TMPDIR="$WORK"
unset OPENAPI_FILE

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
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $label"
    echo "    expected to contain: $needle"
    echo "    actual: $haystack"
    FAIL=$((FAIL + 1))
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -Fq -- "$needle"; then
    echo "  FAIL: $label"
    echo "    did not expect: $needle"
    FAIL=$((FAIL + 1))
  else
    echo "  PASS: $label"
    PASS=$((PASS + 1))
  fi
}

SPEC="$WORK/spec.yaml"
cp "$FIXTURE" "$SPEC"

# validate <METHOD> <path> [body] -> prints messages; status in $RC
validate() {
  OUT=$(printf '%s' "${3:-}" | python3 "$TOOL" validate --spec "$SPEC" "$1" "$2" 2>&1)
  RC=$?
}

echo "=== YAML loader ==="

parsed=$(python3 "$TOOL" to-json --spec "$SPEC")
get() { printf '%s' "$parsed" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(eval('d'+sys.argv[1])))" "$1"; }
assert_eq "literal block keeps lines and indentation" \
  '"Literal block scalar.\n  Indented line kept.\n\nTrailing paragraph.\n"' "$(get "['info']['description']")"
assert_eq "folded block joins lines" '"Folded block scalar joined.\n"' "$(get "['info']['summary']")"
assert_eq "quoted keys stay strings" '["200"]' "$(get "['paths']['/ad_accounts/{ad_account_id}/campaigns']['get']['responses'].keys().__iter__().__class__ and list(d['paths']['/ad_accounts/{ad_account_id}/campaigns']['get']['responses'])")"
assert_eq "flow sequence" '["MAX_BID", "AUTOBID"]' "$(get "['components']['schemas']['AdSetCreateRequest']['properties']['bid_strategy']['enum']")"
assert_eq "single-quoted scalar with embedded double quotes" \
  '"bid_strategy is a plain string, e.g. \"MAX_BID\"."' \
  "$(get "['components']['schemas']['AdSetCreateRequest']['x-spotify-common-mistakes'][0]['correct']")"
assert_eq "integers and booleans are typed" '[1, true]' \
  "$(get "['components']['schemas']['Name']['minLength'] and [d['components']['schemas']['Name']['minLength']-1, d['paths']['/ad_accounts/{ad_account_id}/campaigns']['post']['requestBody']['required']]")"
assert_eq "parse cache is written next to the spec" "yes" "$([ -f "$SPEC.parsed.json" ] && echo yes || echo no)"

printf 'a: &anchor 1\nb: *anchor\npaths: {}\n' > "$WORK/anchors.yaml"
python3 "$TOOL" to-json --spec "$WORK/anchors.yaml" >/dev/null 2>&1
assert_eq "unsupported anchors are rejected, not misread" "2" "$?"

if [ -n "${OPENAPI_TOOL_LIVE_SPEC:-}" ] && command -v ruby >/dev/null 2>&1; then
  mine=$(python3 "$TOOL" to-json --spec "$OPENAPI_TOOL_LIVE_SPEC" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))')
  ref=$(ruby -ryaml -rjson -e 'puts JSON.generate(YAML.load_file(ARGV[0]))' "$OPENAPI_TOOL_LIVE_SPEC" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), sort_keys=True))')
  assert_eq "live spec parses identically to Ruby's YAML" "$ref" "$mine"
fi

echo "=== path matching ==="

validate GET "ad_accounts/abc/campaigns"
assert_eq "relative concrete path matches its template" "0" "$RC"
validate GET "/ads/v3/ad_accounts/abc/campaigns/xyz"
assert_eq "server prefix is stripped" "0" "$RC"
validate GET "ad_accounts/abc/nothing_here"
assert_eq "unknown path is reported as unknown (exit 4)" "4" "$RC"
validate DELETE "ad_accounts/abc/campaigns/xyz"
assert_eq "undefined method on a known path is unknown" "4" "$RC"
assert_contains "lists the methods the path does define" "Defined methods: GET, PATCH" "$OUT"

echo "=== query parameters ==="

validate GET "ad_accounts/abc/campaigns?limit=10&fields=ID&fields=NAME&sort_field=NAME"
assert_eq "valid query with repeated array parameter" "0" "$RC"
validate GET "ad_accounts/abc/campaigns?report_fields=ID"
assert_eq "undefined query parameter only warns (exit 5)" "5" "$RC"
assert_contains "and is labelled a warning" "warning: query.report_fields" "$OUT"
assert_contains "names the undefined parameter" "query.report_fields: is not a query parameter" "$OUT"
validate GET "ad_accounts/abc/campaigns?limit=500"
assert_contains "integer maximum is enforced" "query.limit: 500 is above the maximum 50." "$OUT"
validate GET "ad_accounts/abc/campaigns?limit=ten"
assert_contains "non-integer value is rejected" "query.limit: expected integer, got string." "$OUT"
validate GET "ad_accounts/abc/campaigns?fields=ID,NAME"
assert_contains "comma-joined array values are rejected" 'query.fields[0]: "ID,NAME" is not one of' "$OUT"
validate GET "ad_accounts/abc/campaigns?sort_field=NAME&sort_field=ID"
assert_contains "scalar given twice is rejected" "given 2 times but is not an array" "$OUT"

echo "=== request bodies ==="

validate POST "ad_accounts/abc/campaigns" '{"name":"Spring","objective":"REACH"}'
assert_eq "valid body through allOf" "0" "$RC"
validate POST "ad_accounts/abc/campaigns" '{"name":"Spring"}'
assert_eq "missing required field blocks (exit 3)" "3" "$RC"
assert_contains "required field merged from allOf" "error: body.objective: required field is missing." "$OUT"
validate POST "ad_accounts/abc/campaigns" '{"name":"Spring","objective":null}'
assert_eq "explicit null on a required field blocks" "3" "$RC"
assert_contains "and says it is null" "error: body.objective: required field is null." "$OUT"

echo "=== only missing required values block ==="

# Names and values the spec does not define warn and are sent, because the
# downloaded document can trail the API. Wrong types and bounds are never valid
# and keep blocking (see below).
validate POST "ad_accounts/abc/campaigns" '{"name":"Spring","objective":"OTHER_VALUE"}'
assert_eq "enum value outside the spec's enum only warns" "5" "$RC"
assert_contains "enum warning lists the defined values" 'warning: body.objective: "OTHER_VALUE" is not one of: "REACH", "CLICKS".' "$OUT"
validate POST "ad_accounts/abc/campaigns" '{"name":"Spring","objective":"REACH","extra_field":{"x":1}}'
assert_eq "field the spec does not define only warns" "5" "$RC"
validate POST "ad_accounts/abc/ad_sets" '{"name":"A","bid_strategy":"MAX_BID","budget":{"micro_amount":1,"type":"DAILY"},"targets":{"extra_targets":["X"]},"extra_option":{"id":"x"}}'
assert_eq "nested fields the spec does not define only warn" "5" "$RC"
assert_contains "nested unknown field is named" "warning: body.targets.extra_targets: is not a field the spec defines here." "$OUT"
assert_not_contains "no blocking error when nothing required is missing" "error: " "$OUT"
validate POST "ad_accounts/abc/campaigns" '{"name":"Spring","bid_strategy":{"type":"MAX_BID"}}'
assert_eq "missing required plus unknown field still blocks" "3" "$RC"
assert_contains "reports the blocking error" "error: body.objective: required field is missing." "$OUT"
assert_contains "and the warning alongside it" "warning: body.bid_strategy: is not a field the spec defines here." "$OUT"
validate POST "ad_accounts/abc/campaigns" '{"name":"S","objective":"SALES"}'
assert_contains "minLength through \$ref" "body.name: has 1 characters; at least 2 required." "$OUT"
assert_contains "enum violation lists allowed values" 'body.objective: "SALES" is not one of: "REACH", "CLICKS".' "$OUT"
validate POST "ad_accounts/abc/campaigns" '{"name":"Spring","objective":"REACH","id":"x"}'
assert_contains "read-only field is rejected" "body.id: is read-only and must not be sent." "$OUT"
validate POST "ad_accounts/abc/campaigns" '{"name":"Spring","objectve":"REACH"}'
assert_contains "typo gets a suggestion" "Did you mean 'objective'?" "$OUT"
validate POST "ad_accounts/abc/campaigns" ''
assert_contains "required body is enforced" "requires a request body" "$OUT"
validate POST "ad_accounts/abc/campaigns" '{"name": "Spring",'
assert_contains "malformed JSON is caught before sending" "body: is not valid JSON" "$OUT"
validate GET "ad_accounts/abc/campaigns" '{"x":1}'
assert_contains "body on an operation without one" "does not accept a request body" "$OUT"
validate PATCH "ad_accounts/abc/campaigns/xyz" '{"name":"Renamed"}'
assert_eq "PATCH with a partial body" "0" "$RC"

GOOD_AD_SET='{"name":"A","bid_strategy":"MAX_BID","bid_micro_amount":null,"budget":{"micro_amount":5000000,"type":"DAILY"},"targets":{"geo_targets":{"country_code":"US","region_ids":["1"]},"platforms":["IOS"]},"labels":{"team":"x"}}'
validate POST "ad_accounts/abc/ad_sets" "$GOOD_AD_SET"
assert_eq "valid nested ad set (nullable, additionalProperties)" "0" "$RC"

validate POST "ad_accounts/abc/ad_sets" \
  '{"name":"A","bid_strategy":{"type":"MAX_BID"},"budget":{"micro_amount":0},"targets":{"geo_targets":[{"country_code":"US"}],"platforms":["MOBILE"]},"labels":{"team":1}}'
assert_eq "invalid nested ad set exits 3" "3" "$RC"
assert_contains "object instead of string" "body.bid_strategy: expected string, got object." "$OUT"
assert_contains "x-spotify-common-mistakes hint is attached" 'Hint: bid_strategy is a plain string' "$OUT"
assert_contains "nested required field" "body.budget.type: required field is missing." "$OUT"
assert_contains "nested minimum" "body.budget.micro_amount: 0 is below the minimum 1." "$OUT"
assert_contains "array instead of object" "body.targets.geo_targets: expected object, got array." "$OUT"
assert_contains "enum inside array items" 'body.targets.platforms[0]: "MOBILE" is not one of' "$OUT"
assert_contains "additionalProperties value type" "body.labels.team: expected string, got integer." "$OUT"

validate POST "ad_accounts/abc/ad_sets" \
  '{"name":"A","bid_strategy":"MAX_BID","budget":{"micro_amount":1,"type":"DAILY"},"targets":{"geo_targets":{"country_code":"US","region_ids":["1","2","3","4"]},"extra_ids":["5"]}}'
assert_contains "maxItems" "body.targets.geo_targets.region_ids: has 4 items; at most 3 allowed." "$OUT"
assert_contains "unknown nested field" "body.targets.extra_ids: is not a field the spec defines here." "$OUT"

validate POST "ad_accounts/abc/ad_sets" '{"name":"A","bid_strategy":"MAX_BID","budget":{"micro_amount":1,"type":"DAILY"},"targets":{},"bid_micro_amount":"5"}'
assert_contains "string where integer expected" "body.bid_micro_amount: expected integer, got string." "$OUT"

echo "=== oneOf with discriminator ==="

validate POST "ad_accounts/abc/audiences" '{"audience_type":"CUSTOM","name":"Fans"}'
assert_eq "discriminator selects the custom branch" "0" "$RC"
validate POST "ad_accounts/abc/audiences" '{"audience_type":"LOOKALIKE","name":"Fans"}'
assert_contains "discriminator selects the lookalike branch" "body.seed_audience_id: required field is missing." "$OUT"
validate POST "ad_accounts/abc/audiences" '{"audience_type":"OTHER","name":"Fans"}'
assert_contains "unknown discriminator value" '"OTHER" is not one of: CUSTOM, LOOKALIKE.' "$OUT"
validate POST "ad_accounts/abc/audiences" '{"name":"Fans"}'
assert_contains "missing discriminator" "body.audience_type: required discriminator is missing" "$OUT"

assert_eq "missing discriminator blocks" "3" "$RC"
validate POST "ad_accounts/abc/audiences" '{"audience_type":"OTHER","name":"Fans"}'
assert_eq "discriminator value outside the mapping only warns" "5" "$RC"

# Regression: an object or array discriminator used to crash the validator
# (unhashable dict key), and the wrapper then failed open and sent the request.
# A non-string or null discriminator is never valid, so it blocks.
for bad in '{}' '[]' '["CUSTOM"]' '1' 'true' 'null'; do
  validate POST "ad_accounts/abc/audiences" "{\"audience_type\":$bad,\"name\":\"Fans\"}"
  assert_eq "discriminator $bad blocks, not a crash" "3" "$RC"
  assert_not_contains "discriminator $bad produces no traceback" "Traceback" "$OUT"
done
validate POST "ad_accounts/abc/audiences" '{"audience_type":{},"name":"Fans"}'
assert_contains "non-string discriminator names the type and allowed values" \
  "error: body.audience_type: expected string, got object (one of: CUSTOM, LOOKALIKE)." "$OUT"

echo "=== array item constraints ==="

validate POST "ad_accounts/abc/async_reports" '{"dimensions":["CAMPAIGN_NAME"],"metrics":["IMPRESSIONS"]}'
assert_eq "valid array-of-enum body" "0" "$RC"
validate POST "ad_accounts/abc/async_reports" '{"dimensions":["CAMPAIGN"],"metrics":[]}'
assert_contains "enum on \$ref items is enforced" 'body.dimensions[0]: "CAMPAIGN" is not one of' "$OUT"
assert_contains "minItems on the array is enforced" "body.metrics: has 0 items; at least 1 required." "$OUT"

echo "=== non-JSON bodies ==="

validate POST "ad_accounts/abc/assets" ''
assert_eq "multipart operation is not body-checked" "0" "$RC"

echo "=== describe ==="

desc=$(python3 "$TOOL" describe --spec "$SPEC" POST "ad_accounts/abc/ad_sets")
assert_contains "header names the operation" "POST /ad_accounts/{ad_account_id}/ad_sets  (createAdSet)" "$desc"
assert_contains "path-level \$ref parameter resolved" "ad_account_id*: string uuid" "$desc"
assert_contains "required marker and enum" "bid_strategy*: string; enum: MAX_BID, AUTOBID" "$desc"
assert_contains "nested object expanded" "    micro_amount*: integer int64; minimum=1" "$desc"
assert_contains "common-mistake hint inline" "! bid_strategy is a plain string" "$desc"
assert_contains "additionalProperties shown" "<any key>: string" "$desc"
desc=$(python3 "$TOOL" describe --spec "$SPEC" POST "ad_accounts/abc/campaigns")
assert_contains "allOf merged into one field list" "objective*: string; enum: REACH, CLICKS" "$desc"
assert_not_contains "read-only fields hidden" "  id:" "$desc"
desc=$(python3 "$TOOL" describe --spec "$SPEC" GET "ad_accounts/abc/campaigns")
assert_contains "array query parameter usage" "fields: array of string; items enum: ID, NAME, STATUS; repeat the name for each value" "$desc"

# Regression: body arrays showed only "array of string", even with --full, so
# agents told not to read the raw YAML had no way to see the allowed values.
for mode in "" "--full"; do
  desc=$(python3 "$TOOL" describe --spec "$SPEC" POST "ad_accounts/abc/async_reports" $mode)
  assert_contains "body array shows \$ref item enum ${mode:-(short)}" \
    "dimensions*: array of string; items enum: AD_ACCOUNT_NAME, CAMPAIGN_NAME, AD_SET_NAME" "$desc"
  assert_contains "body array shows inline item enum and array bounds ${mode:-(short)}" \
    "metrics*: array of string; minItems=1; items enum: IMPRESSIONS, SPEND" "$desc"
done
desc=$(python3 "$TOOL" describe --spec "$SPEC" POST "ad_accounts/abc/ad_sets")
assert_contains "nested body array shows its item enum" \
  "platforms: array of string; items enum: ANDROID, DESKTOP, IOS" "$desc"

if [ -n "${OPENAPI_TOOL_LIVE_SPEC:-}" ]; then
  desc=$(python3 "$TOOL" describe --spec "$OPENAPI_TOOL_LIVE_SPEC" POST "ad_accounts/abc/async_reports")
  assert_contains "live async report dimensions list their values" "dimensions*: array of string; items enum: " "$desc"
  assert_contains "live async report metrics list their values" "metrics*: array of string; items enum: " "$desc"
fi
desc=$(python3 "$TOOL" describe --spec "$SPEC" POST "ad_accounts/abc/audiences")
assert_contains "oneOf branches labelled by discriminator" "[when audience_type=LOOKALIKE → LookalikeAudience]" "$desc"
python3 "$TOOL" describe --spec "$SPEC" GET "nope" >/dev/null 2>&1
assert_eq "describe of an unknown operation exits 4" "4" "$?"

echo "=== search ==="

top=$(python3 "$TOOL" search --spec "$SPEC" create ad set --limit 1)
assert_contains "intent search ranks the ad set create first" "POST   /ad_accounts/{ad_account_id}/ad_sets" "$top"
top=$(python3 "$TOOL" search --spec "$SPEC" list campaigns --limit 1)
assert_contains "verb mapping prefers GET for list" "GET    /ad_accounts/{ad_account_id}/campaigns" "$top"

echo "=== spec discovery and openapi-op.sh ==="

python3 "$TOOL" locate >/dev/null 2>&1
assert_eq "no spec located before any fetch" "2" "$?"
python3 "$TOOL" describe GET "ad_accounts/abc/campaigns" >/dev/null 2>&1
assert_eq "describe without a spec asks for the preflight" "2" "$?"

# Fetch through the real script with a stub curl so the pointer is written.
mkdir -p "$WORK/fetchbin"
cat > "$WORK/fetchbin/curl" <<MOCK
#!/bin/bash
prev=""; for a in "\$@"; do [ "\$prev" = "--output" ] && cp "$FIXTURE" "\$a"; prev="\$a"; done
MOCK
chmod +x "$WORK/fetchbin/curl"
FETCHED="$WORK/fetched.yaml"
PATH="$WORK/fetchbin:$PATH" bash "$REPO_ROOT/scripts/fetch-openapi-schema.sh" "$FETCHED"
assert_eq "fetch records the current spec for later shells" "$FETCHED" "$(python3 "$TOOL" locate)"
out=$(bash "$OP" describe GET "ad_accounts/abc/campaigns")
assert_contains "openapi-op.sh describe finds the fetched spec" "GET /ad_accounts/{ad_account_id}/campaigns" "$out"
out=$(bash "$OP" search audience --limit 1)
assert_contains "openapi-op.sh search works" "/audiences" "$out"
assert_eq "OPENAPI_FILE overrides the pointer" "$SPEC" "$(OPENAPI_FILE="$SPEC" python3 "$TOOL" locate)"
bash "$OP" bogus >/dev/null 2>&1
assert_eq "openapi-op.sh rejects an unknown subcommand" "1" "$?"

# Regression: the docs run these directly, so they must be executable. Invoke
# without `bash` so a missing mode bit fails here, not for the user.
for script in "$OP" "$TOOL"; do
  assert_eq "$(basename "$script") is executable on disk" "yes" "$([ -x "$script" ] && echo yes || echo no)"
  if git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 \
    && git -C "$REPO_ROOT" ls-files --error-unmatch "$script" >/dev/null 2>&1; then
    assert_eq "$(basename "$script") is committed as 100755" "100755" \
      "$(git -C "$REPO_ROOT" ls-files -s "$script" | cut -d' ' -f1)"
  fi
done
out=$("$OP" describe GET "ad_accounts/abc/campaigns" 2>&1)
assert_contains "openapi-op.sh runs when invoked directly" "GET /ad_accounts/{ad_account_id}/campaigns" "$out"

touch -t 202001010000 "$FETCHED"
python3 "$TOOL" locate >/dev/null 2>&1
assert_eq "a stale fetched spec is not used" "2" "$?"
touch "$FETCHED"

echo "=== api-request.sh pre-send validation ==="

PROJECT="$WORK/project"
mkdir -p "$PROJECT/.claude" "$WORK/bin"
printf -- '---\naccess_token: "TEST_TOKEN"\nad_account_id: "acct"\nauto_execute: false\n---\n' \
  > "$PROJECT/.claude/spotify-ads-api.local.md"
printf '#!/bin/bash\necho CURL_CALLED\n' > "$WORK/bin/curl"
chmod +x "$WORK/bin/curl"
run_api() {
  env -u CODEX_PROJECT_DIR -u CLAUDE_PLUGIN_ROOT -u CODEX_PLUGIN_ROOT \
    PATH="$WORK/bin:$PATH" CLAUDE_PROJECT_DIR="$PROJECT" bash "$API" test-skill "$@" 2>&1
}

out=$(run_api POST "ad_accounts/{ad_account_id}/campaigns" '{"name":"Spring","objective":"REACH"}')
assert_eq "valid request is sent" "0" "$?"
assert_contains "valid request reaches curl" "CURL_CALLED" "$out"

out=$(run_api POST "ad_accounts/{ad_account_id}/campaigns" '{"name":"Spring"}')
assert_eq "missing required field exits 3" "3" "$?"
assert_not_contains "missing required field never reaches curl" "CURL_CALLED" "$out"
assert_contains "error says the request was not sent" "ERROR: Request not sent." "$out"
assert_contains "error lists the missing field" "  - body.objective: required field is missing." "$out"
assert_contains "error points at openapi-op.sh" "openapi-op.sh describe POST" "$out"
assert_not_contains "error never echoes the token" "TEST_TOKEN" "$out"

out=$(run_api POST "ad_accounts/{ad_account_id}/campaigns" '{"name":"Spring","bogus":1}')
assert_contains "blocked request also lists non-blocking issues" "Also not defined in the spec (not blocking):" "$out"
assert_contains "under their own heading" "  - body.bogus: is not a field the spec defines here." "$out"

# Names and values the spec does not define are sent, with a warning.
out=$(run_api POST "ad_accounts/{ad_account_id}/campaigns" '{"name":"Spring","objective":"OTHER_VALUE","extra_field":1}')
assert_eq "unknown field and enum value are sent" "0" "$?"
assert_contains "and reach curl" "CURL_CALLED" "$out"
assert_contains "with a warning that it was sent anyway" "WARNING: Sent anyway" "$out"
assert_contains "naming the unknown field" "  - body.extra_field: is not a field the spec defines here." "$out"
assert_contains "and the unknown enum value" '  - body.objective: "OTHER_VALUE" is not one of' "$out"
assert_not_contains "warning never echoes the token" "TEST_TOKEN" "$out"

out=$(run_api GET "ad_accounts/{ad_account_id}/campaigns?report_fields=ID")
assert_eq "undefined query parameter is sent" "0" "$?"
assert_contains "with a warning naming it" "query.report_fields" "$out"

out=$(run_api POST "ad_accounts/{ad_account_id}/audiences" '{"audience_type":{},"name":"Fans"}')
assert_eq "object discriminator is blocked by the wrapper" "3" "$?"
assert_not_contains "object discriminator never reaches curl" "CURL_CALLED" "$out"
assert_not_contains "object discriminator does not fail open" "validation was skipped" "$out"

# Wrong shapes are never valid: they still block.
out=$(run_api POST "ad_accounts/{ad_account_id}/ad_sets" '{"name":"A","bid_strategy":{"type":"MAX_BID"},"budget":{"micro_amount":1,"type":"DAILY"},"targets":{"geo_targets":[{"country_code":"US"}]}}')
assert_eq "wrong types still block" "3" "$?"
assert_not_contains "wrong types never reach curl" "CURL_CALLED" "$out"
assert_contains "names the wrongly typed field" "  - body.targets.geo_targets: expected object, got array." "$out"

out=$(run_api POST "ad_accounts/{ad_account_id}/audiences" '{"name":"Fans"}')
assert_eq "missing discriminator is blocked by the wrapper" "3" "$?"
assert_not_contains "missing discriminator never reaches curl" "CURL_CALLED" "$out"

out=$(run_api GET "unlisted/operation")
assert_eq "operation missing from the public spec is still sent" "0" "$?"
assert_contains "with a warning" "sent without spec validation" "$out"
assert_contains "and reaches curl" "CURL_CALLED" "$out"

out=$(SPOTIFY_ADS_SKIP_SPEC_VALIDATION=1 run_api POST "ad_accounts/{ad_account_id}/campaigns" '{"bogus":1}')
assert_contains "explicit opt-out sends unvalidated" "CURL_CALLED" "$out"

rm -f "$FETCHED" "$WORK"/spotify-ads-api-openapi-*.current
out=$(run_api POST "ad_accounts/{ad_account_id}/campaigns" '{"bogus":1}')
assert_contains "no fetched spec: wrapper behaves as before" "CURL_CALLED" "$out"
assert_not_contains "no fetched spec: no warning noise" "WARNING" "$out"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
