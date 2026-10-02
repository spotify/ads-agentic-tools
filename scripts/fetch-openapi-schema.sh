#!/bin/bash
set -uo pipefail

OPENAPI_URL="https://developer.spotify.com/reference/ads-api/v3/api.yaml"

if [ $# -ne 1 ]; then
  echo "Usage: fetch-openapi-schema.sh <destination>" >&2
  exit 1
fi

DESTINATION="$1"
DOWNLOAD_FILE="${DESTINATION}.tmp.$$"
trap 'rm -f "$DOWNLOAD_FILE"' EXIT

# Eval replay mode (see api-request.sh): serve the checked-in snapshot instead.
if [ -n "${EVAL_ADS_API_FIXTURES:-}" ]; then
  case "$EVAL_ADS_API_FIXTURES" in
    /*) SNAPSHOT="$EVAL_ADS_API_FIXTURES/openapi.yaml" ;;
    *)  SNAPSHOT="${CLAUDE_PROJECT_DIR:-$PWD}/$EVAL_ADS_API_FIXTURES/openapi.yaml"
        # Same fallback as api-request.sh when the agent has cd'd away from the workspace.
        [ -f "$SNAPSHOT" ] || SNAPSHOT="${HOME:-}/cwd/$EVAL_ADS_API_FIXTURES/openapi.yaml" ;;
  esac
  cp "$SNAPSHOT" "$DOWNLOAD_FILE" 2>/dev/null || {
    echo "ERROR: Could not fetch the public Spotify Ads API OpenAPI schema from $OPENAPI_URL." >&2
    exit 1
  }
elif ! curl --fail --silent --show-error --location --output "$DOWNLOAD_FILE" "$OPENAPI_URL"; then
  echo "ERROR: Could not fetch the public Spotify Ads API OpenAPI schema from $OPENAPI_URL." >&2
  exit 1
fi

if ! grep -Eq '^openapi: 3\.' "$DOWNLOAD_FILE" || ! grep -Eq '^paths:' "$DOWNLOAD_FILE"; then
  echo "ERROR: The document fetched from $OPENAPI_URL is not a valid Spotify Ads API OpenAPI schema." >&2
  exit 1
fi

mv "$DOWNLOAD_FILE" "$DESTINATION"
