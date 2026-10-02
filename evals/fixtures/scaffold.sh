#!/bin/bash
# Shared eval workspace setup. Writes the dummy settings file and makes the
# workspace a git repository with the replay fixtures inside .git/ads-cache.
# Agents list and read workspace files (an earlier .ads-api/ folder was read
# directly instead of calling the API), but rarely look inside .git. Fixtures
# can't live outside the workspace: plugin eval runs can't read /tmp.
# Usage from a case's scaffold: bash <this> <case> [settings-file] [extra-fixture-dir ...]
set -euo pipefail
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CASE="$1"; shift
SETTINGS="${1:-settings.local.md}"; [ $# -gt 0 ] && shift
FIXTURES=".git/ads-cache"
[ -d .git ] || git init -q
rm -rf "$FIXTURES"; mkdir -p "$FIXTURES" .claude
cp "$HERE/$SETTINGS" .claude/spotify-ads-api.local.md
cp "$HERE/api/default/"* "$FIXTURES/"
for extra in "$@"; do cp "$extra/"* "$FIXTURES/"; done
: > .claude/.api-requests.log
