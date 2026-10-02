#!/bin/bash
# Shared eval workspace setup: a dummy settings file plus the replay fixtures.
# Usage from a case's scaffold: bash <this> [scenario ...]
set -euo pipefail
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
mkdir -p .claude .ads-api
cp "$HERE/settings.local.md" .claude/spotify-ads-api.local.md
cp "$HERE/api/default/"* .ads-api/
: > ads-api-requests.log
for scenario in "$@"; do
  cp "$HERE/api/scenarios/$scenario/"* .ads-api/
done
