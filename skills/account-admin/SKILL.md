---
name: account-admin
description: "Administer Spotify Ads API businesses and ad accounts: discover businesses and accounts, inspect or update supported profile and billing fields, create businesses or ad accounts, list members and roles, invite users, assign ad-account access, update roles, cancel invitations, and remove access. Use when a user asks to find an ad account by ID, audit access, onboard an agency or teammate, manage business/ad-account membership, or update supported account identity details."
---

# Spotify Ads API — Business and Ad Account Administration

Inspect and manage business, ad-account, member, role, and invitation resources.

## Setup

```bash
PLUGIN_ROOT="${CODEX_PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-.}}"
api() { "$PLUGIN_ROOT/scripts/api-request.sh" account-admin "$@"; }
```

## Discovery and audit

There is no top-level `GET /ad_accounts`. Discover accounts through businesses:

```bash
api GET "businesses"
api GET "businesses/<business_id>"
api GET "businesses/<business_id>/ad_accounts"
api GET "ad_accounts/<ad_account_id>"
```

To find a specific account ID, enumerate the current user's businesses and their ad accounts, then match the exact ID. Do not rely on non-unique names.

Audit access:

```bash
api GET "businesses/<business_id>/members"
api GET "businesses/<business_id>/members/<member_id>"
api GET "businesses/<business_id>/members/<member_id>/ad_accounts"
api GET "businesses/<business_id>/invitations"
api GET "ad_accounts/<ad_account_id>/members"
```

Present active members and pending invitations separately. Include exact IDs, email, business role, ad-account role, and assigned accounts.

## Create or update businesses and accounts

Create a business:

```bash
api POST "businesses" \
  '{"name":"Example Agency","type":"AD_AGENCY","business_admin_name":"Alex Smith","business_admin_email":"alex@example.com","business_admin_has_marketing_opt_in":false}'
```

Create an ad account:

```bash
api POST "businesses/<business_id>/ad_accounts" \
  '{"name":"Example Advertiser","type":"BRAND_ADVERTISER","industry":"<industry>","country_code":"US","legal_entity_name":"Example LLC","website":"https://example.com"}'
```

Update an ad account only with public `UpdateAdAccountRequest` fields: `name`, `industry`, `billing_address`, `tax_id`, `tax_ids`, `legal_entity_name`, or `website`.

```bash
api PATCH "ad_accounts/<ad_account_id>" \
  '{"legal_entity_name":"Example LLC","website":"https://example.com"}'
```

Currency, timezone, and country are not updateable fields. Never imply that PATCH can change them.

## Invitations and roles

Invite a business member, optionally with ad-account access:

```bash
api POST "businesses/<business_id>/invitations" \
  '{"email_address":"user@example.com","business_role":"BUSINESS_MEMBER","ad_account_invitations":[{"ad_account_id":"<ad_account_id>","role":"AD_ACCOUNT_CONTRIBUTOR"}]}'
```

Business roles are `BUSINESS_ADMIN` or `BUSINESS_MEMBER`. Read the current enum from the API reference before using an ad-account role; do not guess role values.

Update roles:

```bash
api PATCH "businesses/<business_id>/members/<member_id>/role" \
  '{"role":"BUSINESS_ADMIN"}'
api PATCH "ad_accounts/<ad_account_id>/members/<member_id>" \
  '{"role":"<ad_account_role>"}'
```

Add an existing business member to an ad account:

```bash
api POST "ad_accounts/<ad_account_id>/members" \
  '{"member_id":"<member_id>","role":"<ad_account_role>"}'
```

## Removing access

```bash
api DELETE "businesses/<business_id>/invitations/<invitation_id>"
api DELETE "ad_accounts/<ad_account_id>/members/<member_id>"
api DELETE "businesses/<business_id>/members/<member_id>"
```

Removing a business member also removes their access to assets under that business. Resolve and display the exact person, business, assigned accounts, and effect, then require explicit confirmation immediately before DELETE.

## Mutation protocol

For business creation, account creation, invitations, assignments, role changes, cancellations, and removals:

1. Resolve all IDs with GET.
2. Present a concise before/after plan.
3. Require explicit confirmation immediately before the request, even when `auto_execute` is true.
4. Execute once.
5. Re-read the affected resource to verify the result.

## Guardrails

- Never change the caller's own role or remove their access without an explicit, separately stated request.
- Warn when a role change could remove the last known business administrator; do not proceed until the user confirms the risk.
- Treat email addresses and tax/billing data as sensitive and avoid unnecessary display.
- Do not claim to manage billing currency, timezone, credit lines, invoicing, or unsupported legal-entity eligibility.
- Only retry GET on network errors or 5xx. Never automatically retry POST, PATCH, or DELETE.
- Check `HTTP_STATUS:` first. On 4xx, show the error and stop.
