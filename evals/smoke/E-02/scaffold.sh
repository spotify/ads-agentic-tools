#!/bin/bash
set -euo pipefail
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
bash "$HERE/../../fixtures/scaffold.sh" E-02 settings.local.md "$HERE/api"
