# Create Request Retry Safety

The API request wrapper automatically generates a deterministic key for POST requests on supported create endpoints. This key prevents duplicate entity creation when a request is retried after a timeout or lost response. No user action is required — the protection is on by default.

## How It Works

- The wrapper builds a fingerprint from the base URL, HTTP method, resolved path, and canonical JSON body (keys sorted, whitespace stripped)
- The fingerprint is hashed with SHA-256 — the hash is the key
- The same request always produces the same key, so retries are automatically detected by the server
- Different requests (different body, different path) produce different keys and succeed independently

## Opt Out

The dedup key is on by default for all supported create endpoints. In rare cases you may need to disable it:

- **Intentional duplicate**: you want to create a second entity with the exact same request body (same name, same settings). The deterministic key would block this since the server sees the same key within the 7-day window.
- **PATCH field toggling** (future): toggling a field back and forth (e.g. pausing and resuming) sends the same body, which produces the same key.

To disable for a specific request, use the `--no-dedup-key` flag:

```bash
api --no-dedup-key POST "ad_accounts/{ad_account_id}/campaigns" '{"name":"..."}'
```

This sends the request without an `Idempotency-Key` header. The server treats it as a normal request with no duplicate protection.

## Error Handling

| Response | Action |
|----------|--------|
| Network timeout / lost response | Retry the exact same request — the wrapper produces the same key, so the server detects the duplicate |
| `409` with `error_code: IDEMPOTENCY_REQUEST_IN_PROGRESS` | The original request is still being processed. Honor the `Retry-After` header and wait before retrying |
| `409` with `error_code: IDEMPOTENCY_REQUEST_ALREADY_COMPLETED` | The entity was already created. Use the `resource_uri` from the response to GET the resource and continue |
| `409` with `error_code: IDEMPOTENCY_KEY_REUSED` | A different request body was sent with a key that was already used. Do not retry — start a new request |
| `409` with `error_code: IDEMPOTENCY_OUTCOME_INDETERMINATE` | The previous request's outcome is uncertain. List recent entities to check if it was created, and ask the user how to proceed. Do not auto-retry |
| Validation error (4xx) | Fix the request body and retry — the new body produces a new key automatically |

## Supported Endpoints

- `POST /ad_accounts/{id}/campaigns`
- `POST /ad_accounts/{id}/ad_sets`
- `POST /ad_accounts/{id}/ads`
- `POST /ad_accounts/{id}/drafts/campaigns`
- `POST /ad_accounts/{id}/drafts/ad_sets`
- `POST /ad_accounts/{id}/drafts/ads`
