#!/bin/bash
set -euo pipefail
HERE="$(dirname "$0")"
bash "$HERE/../../fixtures/scaffold.sh"
cp "$HERE/../../fixtures/settings.local.md" .claude/spotify-ads-api.local.md
cp "$HERE/api/"* .ads-api/
