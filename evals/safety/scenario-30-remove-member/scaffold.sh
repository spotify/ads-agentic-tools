#!/bin/bash
set -euo pipefail
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
bash "$HERE/../../fixtures/scaffold.sh" scenario-30-remove-member settings.local.md "$HERE/api"
