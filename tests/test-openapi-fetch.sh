#!/bin/bash
# Regression tests for the live OpenAPI workflow.
# Run: bash tests/test-openapi-fetch.sh

set -uo pipefail

PASS=0
FAIL=0
TEST_TMPDIR=$(mktemp -d)
trap 'rm -rf "$TEST_TMPDIR"' EXIT

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FAKE_BIN="$TEST_TMPDIR/bin"
SCHEMA_FIXTURE="$TEST_TMPDIR/api.yaml"
DESTINATION="$TEST_TMPDIR/downloaded.yaml"

mkdir -p "$FAKE_BIN"

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

printf '%s\n' \
  'openapi: 3.0.3' \
  'paths:' \
  '  /campaigns:' \
  '    post:' \
  '      requestBody: {}' > "$SCHEMA_FIXTURE"

cat > "$FAKE_BIN/curl" <<'MOCK_CURL'
#!/bin/bash
set -uo pipefail

if [ "${MOCK_FETCH_MODE:-success}" = "fail" ]; then
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

if [ "${MOCK_FETCH_MODE:-success}" = "invalid" ]; then
  printf '<html>not an OpenAPI document</html>\n' > "$destination"
else
  cp "$SCHEMA_FIXTURE" "$destination"
fi
MOCK_CURL
chmod +x "$FAKE_BIN/curl"

export SCHEMA_FIXTURE

run_fetch() {
  PATH="$FAKE_BIN:$PATH" "$REPO_ROOT/scripts/fetch-openapi-schema.sh" "$DESTINATION" 2>&1
}

echo "=== successful fetch ==="
output=$(run_fetch)
status=$?
assert_eq "fetch succeeds" "0" "$status"
assert_eq "downloaded document matches source" "$(cat "$SCHEMA_FIXTURE")" "$(cat "$DESTINATION")"
assert_eq "successful fetch is quiet" "" "$output"

echo ""
echo "=== network failure ==="
printf 'preserve existing destination\n' > "$DESTINATION"
output=$(MOCK_FETCH_MODE=fail run_fetch)
status=$?
assert_eq "network failure is reported" "1" "$status"
assert_eq "existing destination is not replaced" 'preserve existing destination' "$(cat "$DESTINATION")"

echo ""
echo "=== invalid document ==="
output=$(MOCK_FETCH_MODE=invalid run_fetch)
status=$?
assert_eq "invalid document is rejected" "1" "$status"
assert_eq "invalid document does not replace destination" 'preserve existing destination' "$(cat "$DESTINATION")"

echo ""
echo "=== skill coverage ==="
missing_skills=""
for skill_file in "$REPO_ROOT"/skills/*/SKILL.md; do
  if grep -Fq 'api() {' "$skill_file" && ! grep -Fq 'references/live-openapi.md' "$skill_file"; then
    missing_skills="${missing_skills}${skill_file#$REPO_ROOT/} "
  fi
done
assert_eq "every API-calling skill requires the live OpenAPI preflight" "" "$missing_skills"

if grep -Fq 'references/live-openapi.md' "$REPO_ROOT/agents/spotify-ads-request-builder.md"; then
  request_builder_preflight="true"
else
  request_builder_preflight="false"
fi
assert_eq "request-builder requires the live OpenAPI preflight" "true" "$request_builder_preflight"

if grep -Fq 'fetch-openapi-schema.sh' "$REPO_ROOT/scripts/api-request.sh"; then
  wrapper_fetches_schema="true"
else
  wrapper_fetches_schema="false"
fi
assert_eq "request wrapper does not download the schema per API call" "false" "$wrapper_fetches_schema"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
