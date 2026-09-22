# Spotify measurement troubleshooting

## Contents

- [Pixel checklist](#pixel-checklist)
- [CAPI checklist](#capi-checklist)
- [Pixel + CAPI deduplication](#pixel--capi-deduplication)
- [Dataset routing](#dataset-routing)
- [Diagnostics interpretation](#diagnostics-interpretation)
- [Receipt versus attribution](#receipt-versus-attribution)
- [Escalation packet](#escalation-packet)

## Pixel checklist

1. Confirm at least 20 minutes have passed since a real event fired.
2. Compare the implemented Pixel key and code with Ads Manager.
3. Confirm the base code is present and runs before/with event code.
4. Confirm event code fires on the intended action or confirmation, not every page load.
5. Inspect browser console and network failures.
6. Check Content Security Policy and privacy/consent tooling.
7. Confirm the site does not install Pixel both directly and through a tag manager.
8. For direct installs, inspect runtime/source for `spdt`; absence in static source is inconclusive for tag-manager installs.
9. Verify redirects retain the `spclid` query parameter.
10. Compare received activity with internal total site activity, not only Spotify-attributed conversions.

Spotify does not troubleshoot unsupported third-party installation products. Isolate whether the issue is Spotify code/configuration or the third-party container before escalation.

## CAPI checklist

### Authentication and routing

- Endpoint is `https://capi.spotify.com/capi-direct/events/`.
- Authorization uses the long-lived CAPI token, not Ads API OAuth.
- Token and `capi_connection_id` belong to the same integration/business.
- The connection has no more than three active token records.
- Server GTM uses a server container and the Spotify CAPI integration tag, not a web container.

### Payload

- top-level envelope is `conversion_events`
- correct `capi_connection_id`
- non-empty `events` array
- allowed source-specific `event_name`
- unique, stable `event_id`
- precise ISO 8601 `event_time`
- `user_data` includes at least one supported identifier
- email/phone are normalized and SHA-256 hashed
- `event_source_url`, if present, begins with `http://` or `https://`
- `action_source`, if present, is `WEB`, `APP`, or `OFFLINE`
- purchases/revenue events carry accurate `currency` and `amount`

For 4xx, fix the payload/auth problem and do not retry unchanged. For 5xx, preserve response, time, and trace ID. Because POST is non-idempotent, confirm whether the stable event ID was received before retrying.

## Pixel + CAPI deduplication

For the same real-world event:

- both integrations belong to the same dataset
- both transports send the same stable `event_id`
- IDs are deterministic at the business-event level, such as an order or lead submission ID
- IDs are not regenerated on every retry/page render
- event names and timestamps describe the same action

Different events must not reuse one ID. Similar aggregate volumes alone do not prove duplication; compare source counts and implementation ID generation.

## Dataset routing

An integration can appear in a dataset's response (e.g. the `pixel` or `capi_integration` field) while its own `dataset_id` field is `null`. This happens when `POST datasets` is used with multiple `integration_ids` to combine integrations that were already assigned to separate auto-created datasets. The CAPI integration's `dataset_id` is typically updated correctly, but the Pixel's may be left as `null`.

When `dataset_id` is `null`, the ingestion pipeline receives events (confirmed by browser network requests reaching `pixels.spotify.com`) but cannot route them to the dataset for diagnostics or attribution. The Pixel datasource will be absent from the diagnostics response entirely.

To fix: remove the affected integration from the dataset (`DELETE datasets/<id>/integrations/<integration_id>`). This moves it to a new auto-created dataset with a proper `dataset_id` link. Then share the new dataset with the ad account. To avoid this issue in the first place, create the Pixel first (it auto-creates a dataset), then create the CAPI connection with `dataset_id` set to the Pixel's dataset.

## Diagnostics interpretation

Dataset diagnostics contain datasources with:

- `datasource_type`: `PIXEL` or `CAPI`
- `datasource_id`
- `granularity`: `HOURLY` or `DAILY`
- timeseries totals and timestamps
- per-event `event_count` and `last_activity_ms`

Empty recent hourly buckets can be normal during the documented processing delay. Convert millisecond timestamps carefully. Compare longer daily history before declaring an outage.

`events_received` on a Pixel or CAPI integration records event types and first-received times. It is useful for capability/history, not as a full real-time health metric.

## Receipt versus attribution

Healthy receipt does not guarantee attributed reporting. Check:

- dataset shared to the correct ad account
- dataset selected as the campaign measurement source
- campaign/report dates and the applicable attribution window
- correct conversion report fields
- event parameters required for revenue-derived metrics
- privacy thresholding: low nonzero conversion counts can be represented as `-5` in Ads API aggregate reporting

The Pixel activity graph is total received activity. It should be compared to total internal site events; campaign tables contain attributed results.

## Escalation packet

Collect without secrets or personal data:

- business, ad account, dataset, integration, and connection IDs
- UTC timestamp and timezone of the issue
- endpoint and HTTP method
- sanitized request field names and response body
- HTTP status and `sp_trace_id`
- first/last known good time
- deployment or GTM publish time
- diagnostic datasource/count evidence
- client ID when contacting Spotify Ads API support
