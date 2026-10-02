#!/bin/bash
set -euo pipefail
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
bash "$HERE/../../fixtures/scaffold.sh" P5-04 settings.local.md "$HERE/api"
