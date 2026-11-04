#!/bin/bash
set -uo pipefail

# Compact view of the workflow's Spotify Ads API OpenAPI document.
#
# Usage:
#   openapi-op.sh describe <METHOD> <path> [--full]   # one operation, $refs resolved
#   openapi-op.sh search <words...> [--limit N]       # find operations by intent
#
# <path> may be a template or a concrete request path, e.g.
#   openapi-op.sh describe POST "ad_accounts/{ad_account_id}/drafts/ad_sets"
#   openapi-op.sh search create lookalike audience
#
# Reads the document fetched by fetch-openapi-schema.sh (or $OPENAPI_FILE, or
# --spec FILE); never downloads anything. Descriptions are shortened with "…";
# pass --full for complete text.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

case "${1:-}" in
  describe|search) ;;
  *)
    sed -n '4,16p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 1
    ;;
esac

for py in python3 python py; do
  if command -v "$py" >/dev/null 2>&1; then
    exec "$py" "$SCRIPT_DIR/openapi_tool.py" "$@"
  fi
done
echo "ERROR: python3 is required for openapi-op.sh." >&2
exit 1
