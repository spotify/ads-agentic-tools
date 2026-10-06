#!/bin/bash
# Shared eval workspace setup. Writes the dummy settings file and makes the
# workspace a git repository with the replay fixtures inside .git/ads-cache.
# Agents list and read workspace files (an earlier .ads-api/ folder was read
# directly instead of calling the API), but rarely look inside .git. Fixtures
# can't live outside the workspace: plugin eval runs can't read /tmp.
# Usage: bash <this> [settings-file] [extra-fixture-dir ...]
set -euo pipefail
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
SETTINGS="${1:-settings.local.md}"; [ $# -gt 0 ] && shift
FIXTURES=".git/ads-cache"
[ -d .git ] || git init -q
rm -rf "$FIXTURES"; mkdir -p "$FIXTURES" .claude
cp "$HERE/$SETTINGS" .claude/spotify-ads-api.local.md
cp "$HERE/api/default/"* "$FIXTURES/"
for extra in "$@"; do cp "$extra/"* "$FIXTURES/"; done
# Download the current public OpenAPI document for the replayed
# fetch-openapi-schema.sh to serve. A copy under a day old is reused so a suite
# run downloads it once. Without it every case would test the wrong thing, so a
# failed download fails the case.
SPEC_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/ads-plugin-evals/openapi.yaml"
if [ -z "$(find "$SPEC_CACHE" -mmin -1440 2>/dev/null)" ]; then
  mkdir -p "$(dirname "$SPEC_CACHE")"
  env -u EVAL_ADS_API_FIXTURES bash "$HERE/../../scripts/fetch-openapi-schema.sh" "$SPEC_CACHE.tmp"
  mv "$SPEC_CACHE.tmp" "$SPEC_CACHE"
fi
cp "$SPEC_CACHE" "$FIXTURES/openapi.yaml"
: > .claude/.api-requests.log
