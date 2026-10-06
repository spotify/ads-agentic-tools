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
# Runs in the fresh eval workspace. Refuse to run anywhere that already has a
# settings file, such as a plugin checkout, so it can't overwrite real settings.
if [ -e .claude/spotify-ads-api.local.md ]; then
  echo "ERROR: $PWD/.claude/spotify-ads-api.local.md already exists; run this in an empty workspace." >&2
  exit 1
fi
[ -d .git ] || git init -q
rm -rf "$FIXTURES"; mkdir -p "$FIXTURES" .claude
cp "$HERE/$SETTINGS" .claude/spotify-ads-api.local.md
cp "$HERE/api/default/"* "$FIXTURES/"
for extra in "$@"; do cp "$extra/"* "$FIXTURES/"; done
# Download the current public OpenAPI document for the replayed
# fetch-openapi-schema.sh to serve. Without it every case would test the wrong
# thing, so a failed download fails the case.
env -u EVAL_ADS_API_FIXTURES bash "$HERE/../../scripts/fetch-openapi-schema.sh" "$FIXTURES/openapi.yaml"
: > .claude/.api-requests.log
