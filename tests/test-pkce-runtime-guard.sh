#!/bin/bash
# Fail if OAuth runtime paths reintroduce secret-based authentication.

set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
RUNTIME_PATHS=(
  "$ROOT/hooks/check-token.sh"
  "$ROOT/skills/configure/scripts/oauth-flow.py"
  "$ROOT/skills/configure/scripts/refresh-token.py"
)

if rg -n 'client_secret|client-secret|Authorization:[[:space:]]*Basic|security[[:space:]]+(find|add)-generic-password' "${RUNTIME_PATHS[@]}"; then
  echo "Secret-based OAuth contract found in a runtime path." >&2
  exit 1
fi

echo "PKCE runtime guard passed."
