# Live OpenAPI Preflight

Use the public Spotify Ads API OpenAPI document as the source of truth for every Ads
API v3 workflow. This preflight is agent-driven so it covers the full operation contract,
including parameters and request bodies, without adding another network request to each
`api()` invocation.

## 1. Fetch Once Per Workflow

Before the first Ads API v3 call, create a temporary file and fetch the current document:

```bash
OPENAPI_FILE=$(mktemp "${TMPDIR:-/tmp}/spotify-ads-api-openapi.XXXXXX")
"$PLUGIN_ROOT/scripts/fetch-openapi-schema.sh" "$OPENAPI_FILE"
```

If the fetch fails or the document is invalid, stop before making an Ads API v3 call and
explain that the current API contract could not be checked. OAuth token exchange and
uploads to API-provided signed asset URLs are transport exceptions, not Ads API v3
operations.

## 2. Inspect Every Planned Operation

Use the same downloaded document for all calls in the current workflow. Before each
call, locate its exact path and HTTP method, then inspect and follow:

- path and query parameters, including required values, types, formats, and enums;
- `requestBody` content for POST, PUT, and PATCH requests;
- required properties, property types, formats, enums, arrays, and nested objects;
- local `$ref` links under `components`, following them until the effective schema is
  understood;
- whether `additionalProperties`, nullable fields, or composition keywords such as
  `allOf`, `oneOf`, and `anyOf` affect the proposed payload.

Construct the request only after comparing the final method, path, parameters, and body
with those definitions. OpenAPI is the baseline API contract; apply live ad product
catalog rules as an additional validation layer where required.

## 3. Clean Up

Remove `OPENAPI_FILE` after the workflow. Do not reuse it for a later user operation;
fetch the public document again so the next workflow starts with the current contract.
