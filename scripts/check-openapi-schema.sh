#!/bin/bash
set -uo pipefail

# Fetch the public Spotify Ads API OpenAPI schema and optionally verify that an
# HTTP method/path is documented before api-request.sh sends the request.

OPENAPI_URL="https://developer.spotify.com/reference/ads-api/v3/api.yaml"

fetch_schema() {
  local destination="$1"

  if ! curl --fail --silent --show-error --location --output "$destination" "$OPENAPI_URL"; then
    echo "ERROR: Could not fetch the public Spotify Ads API OpenAPI schema from $OPENAPI_URL. No API request was sent." >&2
    return 1
  fi

  if ! grep -Eq '^openapi: 3\.' "$destination" || ! grep -Eq '^paths:' "$destination"; then
    echo "ERROR: The document fetched from $OPENAPI_URL is not a valid Spotify Ads API OpenAPI schema. No API request was sent." >&2
    return 1
  fi
}

if [ "${1:-}" = "--fetch" ]; then
  if [ $# -ne 2 ]; then
    echo "Usage: check-openapi-schema.sh --fetch <destination>" >&2
    exit 1
  fi

  fetch_schema "$2"
  exit $?
fi

if [ $# -ne 2 ]; then
  echo "Usage: check-openapi-schema.sh <METHOD> <path>" >&2
  echo "       check-openapi-schema.sh --fetch <destination>" >&2
  exit 1
fi

METHOD=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
REQUEST_PATH="/${2#/}"
REQUEST_PATH="${REQUEST_PATH%%\?*}"
SCHEMA_FILE=$(mktemp "${TMPDIR:-/tmp}/spotify-ads-api-openapi.XXXXXX")
trap 'rm -f "$SCHEMA_FILE"' EXIT

fetch_schema "$SCHEMA_FILE" || exit 1

if ! REQUEST_METHOD="$METHOD" REQUEST_PATH="$REQUEST_PATH" awk '
  function path_matches(template, requested, template_parts, requested_parts, template_count, requested_count, part_index) {
    template_count = split(template, template_parts, "/")
    requested_count = split(requested, requested_parts, "/")

    if (template_count != requested_count) {
      return 0
    }

    for (part_index = 1; part_index <= template_count; part_index++) {
      if (template_parts[part_index] ~ /^\{[^}]+\}$/) {
        continue
      }

      if (template_parts[part_index] != requested_parts[part_index]) {
        return 0
      }
    }

    return 1
  }

  /^  \/[^[:space:]]+:$/ {
    current_path = $0
    sub(/^  /, "", current_path)
    sub(/:$/, "", current_path)
    next
  }

  /^    (get|post|put|patch|delete|options|head|trace):$/ {
    operation = $1
    sub(/:$/, "", operation)

    if (operation == ENVIRON["REQUEST_METHOD"] && path_matches(current_path, ENVIRON["REQUEST_PATH"])) {
      found = 1
      exit
    }
  }

  END { exit found ? 0 : 1 }
' "$SCHEMA_FILE"; then
  echo "ERROR: $1 $REQUEST_PATH is not documented in the current Spotify Ads API OpenAPI schema. No API request was sent." >&2
  exit 1
fi
