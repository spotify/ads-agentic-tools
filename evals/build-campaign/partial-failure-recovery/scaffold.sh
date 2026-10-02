#!/bin/bash
set -euo pipefail
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
bash "$HERE/../../fixtures/scaffold.sh" partial-failure-recovery settings.local.md "$HERE/api" "$HERE/../../fixtures/api/scenarios/draft-ad-set-fails"
