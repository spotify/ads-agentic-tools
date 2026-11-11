#!/bin/bash
# Audience estimates must always carry bid_micro_amount, including with AUTOBID.
# The AUTOBID omission applies only to ad set payloads; an estimate without a bid
# is rejected with "Validation error on field bidMicroAmount ... must not be null".
# These checks keep the skill guidance that agents copy estimate bodies from
# consistent with that rule. Pre-send blocking is covered in test-openapi-tool.sh.
# Run: bash tests/test-audience-estimates.sh

set -uo pipefail

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PASS=0
FAIL=0

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# Print each estimate example in a file, one per record. Two forms exist:
# an `api POST "estimates/audience"` call (ends at the line closing the quoted
# JSON body) and a "`POST /estimates/audience` example body:" label followed by
# a ```json block (ends at the closing fence).
estimate_examples() {
  awk '
    /api POST "estimates\/audience"/ { grab = "call"; buf = "" }
    /`POST \/estimates\/audience` example body/ { grab = "label"; buf = ""; next }
    grab == "call" {
      buf = buf $0 "\n"
      if ($0 ~ /}'"'"'[[:space:]]*$/) { printf "%s\036", buf; grab = "" }
    }
    grab == "label" {
      if ($0 ~ /^```json/) { grab = "fence"; next }
      if ($0 !~ /^[[:space:]]*$/) grab = ""
    }
    grab == "fence" {
      if ($0 ~ /^```/) { printf "%s\036", buf; grab = "" } else buf = buf $0 "\n"
    }
  ' "$1"
}

ESTIMATE_PATTERN='api POST "estimates/audience"|`POST /estimates/audience` example body'

# Print one markdown section: from a heading line matching $2 to the next
# heading of the same or higher level.
section() {
  awk -v pat="$2" '
    !inside && index($0, pat) == 1 { inside = 1; match($0, /^#+/); level = RLENGTH; print; next }
    inside && /^#+ / { match($0, /^#+/); if (RLENGTH <= level) exit }
    inside { print }
  ' "$1"
}

echo "=== every estimate example includes bid_micro_amount ==="

files=$(git -C "$REPO_ROOT" grep -l -E "$ESTIMATE_PATTERN" -- skills agents)
[ -n "$files" ] || fail "found no estimate examples to check"
for f in $files; do
  n=0
  while IFS= read -r -d $'\036' example; do
    n=$((n + 1))
    if printf '%s' "$example" | grep -q '"bid_micro_amount"'; then
      pass "$f example $n includes bid_micro_amount"
    else
      fail "$f example $n omits bid_micro_amount"
    fi
  done < <(estimate_examples "$REPO_ROOT/$f")
  [ "$n" -gt 0 ] || fail "$f: could not parse its estimate example"
done

echo "=== drafts points to an estimate example that includes the bid ==="

DRAFTS="$REPO_ROOT/skills/drafts/SKILL.md"
BUILD="$REPO_ROOT/skills/build-campaign/SKILL.md"

if grep -qF 'run the audience estimate from `build-campaign` Step 2.5' "$DRAFTS"; then
  pass "drafts sends agents to build-campaign Step 2.5 for the estimate"
  target=$(section "$BUILD" "## Step 2.5")
  if [ -z "$target" ]; then
    fail "build-campaign has no Step 2.5 heading for drafts to point at"
  elif printf '%s\n' "$target" | grep -q 'api POST "estimates/audience"' \
    && printf '%s\n' "$target" | grep -q '"bid_micro_amount"'; then
    pass "build-campaign Step 2.5 holds an estimate example with bid_micro_amount"
  else
    fail "build-campaign Step 2.5 lacks an estimate example with bid_micro_amount"
  fi
elif estimate_examples "$DRAFTS" | grep -q '"bid_micro_amount"'; then
  pass "drafts has its own estimate example with bid_micro_amount"
else
  fail "drafts neither points to build-campaign Step 2.5 nor has its own estimate example"
fi

echo "=== the AUTOBID exception is scoped to ad sets ==="

for f in skills/drafts/SKILL.md skills/ads/SKILL.md skills/build-campaign/SKILL.md \
         skills/api-reference/references/api-behaviors.md; do
  if grep -iqE 'AUTOBID.*(only to ad set payloads|not to the estimate)|(even when|even if).*AUTOBID|estimate.*on the basis of AUTOBID' "$REPO_ROOT/$f"; then
    pass "$f says AUTOBID does not exempt estimates from the bid"
  else
    fail "$f does not say AUTOBID leaves the estimate bid required"
  fi
done

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
