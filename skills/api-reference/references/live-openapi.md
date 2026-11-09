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

The fetch also records the document's location, so later shells find it without
`OPENAPI_FILE` being exported. From then on, `api()` checks every request against it
before sending (see section 3).

## 2. Inspect Every Planned Operation

Use the same downloaded document for all calls in the current workflow. Do not read the
raw YAML: it is over 400 KB. Use the compact view, which resolves every `$ref`, merges
`allOf`, labels `oneOf` branches by discriminator, marks required fields with `*`, hides
read-only fields, and shows the spec's common-mistake hints inline (`!`):

```bash
"$PLUGIN_ROOT/scripts/openapi-op.sh" describe POST "ad_accounts/{ad_account_id}/drafts/ad_sets"
"$PLUGIN_ROOT/scripts/openapi-op.sh" describe GET "ad_accounts/{ad_account_id}/aggregate_reports" --full
"$PLUGIN_ROOT/scripts/openapi-op.sh" search create lookalike audience   # when the endpoint is not known
```

Descriptions are shortened with `…`; add `--full` when the shortened text is not enough
to decide a value. Before each call, locate its exact path and HTTP method, then inspect
and follow:

- path and query parameters, including required values, types, formats, and enums;
- `requestBody` content for POST, PUT, and PATCH requests;
- required properties, property types, formats, enums, arrays, and nested objects;
- local `$ref` links under `components`, following them until the effective schema is
  understood;
- whether `additionalProperties`, nullable fields, or composition keywords such as
  `allOf`, `oneOf`, and `anyOf` affect the proposed payload.

> **Required fields are mandatory for every request.** Every field the spec marks as
> required MUST ALWAYS be present in the payload, for every operation. This includes
> required fields inside nested objects and array items, resolved through `$ref`,
> `allOf`, `oneOf`, `anyOf`, and `items`. This is the baseline for every request: never
> omit a required field because a doc suggests it is not needed. If a value is unknown,
> ask the user or derive it; do not drop the field.

> **Only defined fields may be sent.** Send only fields the spec defines as properties of
> the operation's parameters or request schema. A field name that appears only in
> description text is not part of the public contract: never send it, and never suggest
> it to the user.

Construct the request only after comparing the final method, path, parameters, and body
with those definitions. OpenAPI is the baseline API contract; apply live ad product
catalog rules as an additional validation layer where required.

## 3. Pre-Send Validation

Once the document is fetched, `api()` validates each request against it locally before
sending anything. It checks query parameters and the JSON body at every depth.

- **Blocks**: missing or null required fields, missing required query parameters,
  bodies, and `oneOf` discriminators, wrong types, length, range, and item-count
  bounds, read-only fields, and invalid JSON. The wrapper exits with status 3, prints
  `ERROR: Request not sent.` with one line per problem, and sends nothing. The request
  never reached the API, so this is not a failed POST or PATCH: fix the listed fields
  and send the corrected request. Never resend the same request unchanged.
- **Warns and sends**: fields and query parameters the spec does not define, and enum or
  discriminator values outside the spec's lists. The request goes out, and stderr starts
  with `WARNING: Sent anyway` and lists each one. The downloaded document can trail the
  API, so these are not blocked. This does not relax step 2: send only fields and values
  the spec defines. Treat each warning as a mistake to fix before the next request,
  usually a typo (the warning suggests the closest defined name) or a guessed field. If
  the API rejects the request, start from the warning.

This check enforces the OpenAPI contract only. It does not replace the ad product
catalog rules, audience estimates, or the API's own validation. An operation the public
spec does not list is sent with a `WARNING` and is not validated. When no document has
been fetched, requests are sent without validation, so always run step 1 first.

## 4. Clean Up

Remove `OPENAPI_FILE` after the workflow. Do not reuse it for a later user operation;
fetch the public document again so the next workflow starts with the current contract.
