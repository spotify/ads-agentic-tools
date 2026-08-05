#!/bin/bash
# Test that update_setting and token substitution handle metacharacters safely.
# Run: bash hooks/test-token-interpolation.sh

set -euo pipefail

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

# --- update_setting tests (awk-based) ---

update_setting() {
  local key="$1" val="$2" file="$3"
  local tmp="${file}.tmp.$$"
  AWK_KEY="$key" AWK_VAL="$val" awk 'BEGIN{k=ENVIRON["AWK_KEY"]; v=ENVIRON["AWK_VAL"]; found=0} {if ($0 ~ "^"k": " && !found) {print k": \""v"\""; found=1} else print}' "$file" > "$tmp" && mv "$tmp" "$file"
}

echo "=== update_setting ==="

# Normal token
f="$TMPDIR/normal.md"
printf 'access_token: "old_token"\nother: "keep"\n' > "$f"
update_setting "access_token" "new_token_abc123" "$f"
assert_eq "normal token" 'access_token: "new_token_abc123"' "$(grep '^access_token:' "$f")"
assert_eq "other key preserved" 'other: "keep"' "$(grep '^other:' "$f")"

# Token with pipe (sed delimiter)
f="$TMPDIR/pipe.md"
printf 'access_token: "old"\n' > "$f"
update_setting "access_token" "token|with|pipes" "$f"
assert_eq "pipe in token" 'access_token: "token|with|pipes"' "$(grep '^access_token:' "$f")"

# Token with ampersand (sed backreference)
f="$TMPDIR/amp.md"
printf 'access_token: "old"\n' > "$f"
update_setting "access_token" "token&with&amps" "$f"
assert_eq "ampersand in token" 'access_token: "token&with&amps"' "$(grep '^access_token:' "$f")"

# Token with backslash
f="$TMPDIR/bs.md"
printf 'access_token: "old"\n' > "$f"
update_setting "access_token" 'token\with\backslashes' "$f"
assert_eq "backslash in token" 'access_token: "token\with\backslashes"' "$(grep '^access_token:' "$f")"

# Token with all sed metacharacters combined
f="$TMPDIR/combo.md"
printf 'access_token: "old"\nrefresh_token: "keep_me"\n' > "$f"
update_setting "access_token" 'a|b&c\d' "$f"
assert_eq "combined metacharacters" 'access_token: "a|b&c\d"' "$(grep '^access_token:' "$f")"
assert_eq "refresh_token untouched" 'refresh_token: "keep_me"' "$(grep '^refresh_token:' "$f")"

# Only first occurrence is replaced
f="$TMPDIR/dup.md"
printf 'access_token: "first"\naccess_token: "second"\n' > "$f"
update_setting "access_token" "replaced" "$f"
count=$(grep -c '^access_token: "replaced"' "$f")
assert_eq "only first occurrence replaced" "1" "$count"

# --- token substitution tests (set -f) ---

echo ""
echo "=== token substitution in command ==="

do_substitution() {
  local modified_command="$1" access_token="$2" new_token="$3"
  set -f
  modified_command="${modified_command//"$access_token"/$new_token}"
  set +f
  echo "$modified_command"
}

# Normal substitution
result=$(do_substitution "curl -H 'Bearer abc123' https://api.example.com" "abc123" "xyz789")
assert_eq "normal substitution" "curl -H 'Bearer xyz789' https://api.example.com" "$result"

# Token with glob star
result=$(do_substitution "curl -H 'Bearer to*ken' https://api.example.com" "to*ken" "new_token")
assert_eq "star in token" "curl -H 'Bearer new_token' https://api.example.com" "$result"

# Token with glob question mark
result=$(do_substitution "curl -H 'Bearer to?ken' https://api.example.com" "to?ken" "new_token")
assert_eq "question mark in token" "curl -H 'Bearer new_token' https://api.example.com" "$result"

# Token with brackets
result=$(do_substitution "curl -H 'Bearer to[k]en' https://api.example.com" "to[k]en" "new_token")
assert_eq "brackets in token" "curl -H 'Bearer new_token' https://api.example.com" "$result"

# Token with all glob metacharacters
result=$(do_substitution "curl -H 'Bearer a*b?c[d]' https://api.example.com" 'a*b?c[d]' "safe_token")
assert_eq "combined glob chars" "curl -H 'Bearer safe_token' https://api.example.com" "$result"

# --- summary ---

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
