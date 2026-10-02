#!/bin/bash
set -euo pipefail
HERE="$(dirname "$0")"
bash "$HERE/../../fixtures/scaffold.sh"
cp "$HERE/api/"* .ads-api/
