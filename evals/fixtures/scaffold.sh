#!/bin/bash
# Shared eval workspace setup. Writes the dummy settings file into the workspace
# and the replay fixtures to /tmp/spotify-ads-cache/<case>, outside the workspace,
# so the agent under test can't find and read them instead of calling the API.
# Usage from a case's scaffold: bash <this> <case> [settings-file] [extra-fixture-dir ...]
set -euo pipefail
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CASE="$1"; shift
SETTINGS="${1:-settings.local.md}"; [ $# -gt 0 ] && shift
FIXTURES="/tmp/spotify-ads-cache/$CASE"
rm -rf "$FIXTURES"; mkdir -p "$FIXTURES" .claude
cp "$HERE/$SETTINGS" .claude/spotify-ads-api.local.md
cp "$HERE/api/default/"* "$FIXTURES/"
for extra in "$@"; do cp "$extra/"* "$FIXTURES/"; done
: > .claude/.api-requests.log
