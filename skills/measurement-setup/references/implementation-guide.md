# Spotify measurement implementation guide

Use this reference for implementation advice. The Ads API manages resources; website, server, GTM, consent, and secret-manager changes remain with the user's implementation owners.

## Contents

- [Choose the topology](#choose-the-topology)
- [Event mapping](#event-mapping)
- [Parameters](#parameters)
- [Direct CAPI contract](#direct-capi-contract)
- [Pixel implementation](#pixel-implementation)
- [CAPI with server GTM](#capi-with-server-gtm)
- [Advanced matching and privacy](#advanced-matching-and-privacy)
- [Verification boundaries](#verification-boundaries)

## Choose the topology

| Need | Recommended source |
|---|---|
| Browser page views and website actions | Spotify Pixel |
| Server-side web, app, or offline events | CAPI |
| Browser coverage plus server reliability | Pixel and CAPI in one dataset |
| App attribution through an MMP | Mobile app resource plus supported MMP |

A dataset groups Pixel and CAPI integrations. When both sources describe the same real-world event, send the same stable `event_id` from both sources. Do not generate a different ID per transport.

## Event mapping

Supported business events are:

- page view: Pixel command `view`; CAPI `VIEW`
- product view: Pixel command `product`; CAPI `PRODUCT`
- lead: Pixel command `lead`; CAPI `LEAD`
- add to cart: Pixel command `addtocart`; CAPI `ADD_TO_CART`
- start checkout: Pixel command `checkout`; CAPI `CHECK_OUT`
- purchase: Pixel command `purchase`; CAPI `PURCHASE`
- sign up: CAPI `SIGN_UP`; use the corresponding Ads Manager Pixel event
- custom: `CUSTOM_EVENT_1` through `CUSTOM_EVENT_5`

The Ads API diagnostic schema may return internal signal names such as `CHECKOUT`, `ADDTOCART`, or `SIGNUP`. Do not rewrite an implementation payload from diagnostic spelling alone; use the source-specific values above.

Reserve custom slots in a shared data dictionary with owner, trigger, source, expected volume, and parameters. Custom slots cannot currently be renamed.

## Parameters

Pixel supports these documented parameters where relevant:

- `quantity` (integer)
- `category` and `type` (lead strings)
- `currency` (string)
- `value` (float)
- `is_new_customer` (boolean)
- `product_id`, `product_name`, `product_type`, `product_vendor` (strings)
- `variant_id`, `variant_name` (strings)
- `event_id` (string, especially for deduplication)
- `line_items` (list/object)
- `discount_code` (string)

Revenue reporting such as attributed revenue, AOV, ROAS, and CAC requires appropriate revenue events with both value and currency. Do not confuse Pixel's `value` with CAPI's `event_details.amount`.

Direct CAPI `event_details` may include `currency`, `amount`, `content_category`, and `content_name`. It is optional, but include accurate currency and amount for purchase/revenue analysis. The `content_category` value must correspond to Google's Product Taxonomy; free-form strings are rejected with a 400 error. Omit the field if a valid taxonomy value is not available.

## Direct CAPI contract

Endpoint:

```text
POST https://capi.spotify.com/capi-direct/events/
Authorization: Bearer <CAPI_ACCESS_TOKEN>
Content-Type: application/json
```

Shape:

```json
{
  "conversion_events": {
    "capi_connection_id": "<CAPI_CONNECTION_ID>",
    "events": [{
      "event_name": "PURCHASE",
      "event_id": "<STABLE_ORDER_OR_EVENT_ID>",
      "event_time": "2026-01-23T12:34:56.000Z",
      "user_data": {
        "ip_address": "<CLIENT_IP>",
        "device_id": "<DEVICE_ID>",
        "hashed_emails": ["<SHA256_EMAIL>"],
        "hashed_phone_number": "<SHA256_PHONE>"
      },
      "event_details": {
        "currency": "USD",
        "amount": 100.0,
        "content_name": "Premium subscription"
      },
      "event_source_url": "https://example.com/confirmation",
      "action_source": "WEB",
      "opt_out_targeting": false
    }]
  }
}
```

Required per event:

- connection ID
- allowed event name
- unique event ID
- precise ISO 8601 event time, preferably UTC
- `user_data` with at least one accepted identifier

Accepted identifiers are client IP, device ID, SHA-256 email, and SHA-256 phone. Include IP plus device ID when legitimately available. Normalize email/phone by trimming and lowercasing before SHA-256 hashing. Follow the current developer contract for whether a particular device ID is raw or hashed; the published guide contains inconsistent wording between its example and field note, so do not transform a production device ID without confirming the integration specification with Spotify.

Optional `action_source` values are `WEB`, `APP`, and `OFFLINE`. Set `opt_out_targeting: true` when the event may be used for attribution but must not be used for retargeting.

## Pixel implementation

- Install the base code sitewide, or at minimum on three pages; the document header is preferred.
- The base code measures page views.
- Fire additional events on the actual action or confirmation, not merely on an unrelated page load.
- In web GTM, use Custom HTML tags and make sure base code accompanies every Pixel event.
- Do not install both direct code and a tag manager version.
- Spotify appends `spclid` to ad landing URLs. Preserve query parameters through redirects so the Pixel can capture it.
- Removing an event means stopping/removing its code; events cannot be deleted from Ads Manager.

## CAPI with server GTM

Use a GTM **server container**, not a web container, and Spotify's CAPI third-party integration tag. The tag needs the CAPI token and connection ID. Automatic provisioning requires appropriate Google Cloud billing/project permissions; manual Cloud Run setup requires the corresponding GCP permissions. Keep token and connection ID from the same business integration.

## Advanced matching and privacy

Automatic advanced matching scans form fields for supported identifiers and hashes them with SHA-256 in the browser. Manual matching maps fields explicitly. Obtain approval before enabling either mode and select only data collected with a lawful, disclosed purpose.

The API enum supports `EMAIL`, `PHONE`, `FIRST_NAME`, `LAST_NAME`, `DATE_OF_BIRTH`, `GENDER`, `CITY`, `STATE`, `ZIP`, `COUNTRY`, and `EXTERNAL_ID`. The current help-center UI guidance lists a narrower set. Treat API capability and UI availability as separate facts.

Never print raw identifiers, hashes that can be linked back to a user, CAPI tokens, or complete production payloads in diagnostic output.

## Verification boundaries

Allow at least 20 minutes after an implementation begins firing before treating empty Ads Manager diagnostics as a failure. The Pixel event activity chart reflects all received site activity, not conversions attributed to Spotify ads. Campaign attribution must be checked in reporting, and low conversion counts may be privacy-thresholded.
