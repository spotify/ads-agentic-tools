# Ad Product Catalog Validation

Use this procedure before every campaign, ad set, or ad `POST` or `PATCH`, including
draft creation and edits, clone operations, bulk changes, and replacement ads.

The hard invariant is: **never send a request with a known, unresolved ad product
catalog violation.** Printing a checklist is not validation and is not required.

## 1. Fetch Rules Once Per Workflow

Fetch the catalog at the start of the current create or update workflow:

```bash
api GET "ad_product_catalog"
```

Reuse that response while assembling and executing the current workflow. Do not reuse
a response retained from an earlier operation or attempt to maintain a timed session
cache. If the catalog request fails, do not execute a mutation that depends on it.

The catalog layers product-specific restrictions on top of the OpenAPI schema:

- OpenAPI defines request shapes and field types.
- The catalog defines product-specific allowed values, required or forbidden fields,
  constraints, restrictions, frequency caps, and cross-field rules.
- For creates, apply the matching entity's `create` and `both` sections.
- For updates, apply the matching entity's `update` and `both` sections. A missing
  operation section means there are no additional rules in that section; `both` still
  applies.

When the catalog explicitly lists product-specific allowed values, use that live list
for product validation; some deprecated enums in the committed OpenAPI may lag the
catalog. OpenAPI still governs whether the field exists and what shape and type it has.
If the catalog requires a field or shape that OpenAPI cannot represent, do not invent a
payload or claim that validation passed. Stop before the mutation and explain the
conflict.

## 2. Resolve the Ad Product

- For campaign creation, use the request's `ad_product`. Treat an omitted value,
  `UNSET`, or `UNKNOWN` as `AUCTION`.
- For a hierarchy created in the current workflow, carry that resolved product forward
  to its ad sets and ads; do not refetch the campaign merely to rediscover it.
- For existing ad sets and ads, fetch the entity chain needed to reach the parent
  campaign. Use `ad_product` when the campaign response provides it.
- When an existing campaign response omits `ad_product`, use `AUCTION` only when the
  request context and entity data do not indicate a reserved `CONTENT` or `FPMNG`
  campaign. If the user, source operation, pricing fields, or entity configuration
  indicates a reserved product, obtain an authoritative product choice instead of
  silently defaulting to `AUCTION`.
- Do not infer a reserved product solely from a campaign objective.

For bulk operations, resolve each distinct campaign once and group entities by resolved
product. For clones, validate against the product that the new campaign request will
actually create, not merely the source campaign's product.

## 3. Validate the Final Effective Entity

Assemble all fields before validation.

- **Create:** validate the final request body plus any parent or asset data referenced
  by cross-entity rules.
- **Update:** fetch the current entity, deep-merge the proposed PATCH into it, and
  validate the resulting effective entity. Do not validate only the changed fields.
- On update, apply rules conditioned on a value being new or changed only when the
  PATCH actually changes that value. Do not reject a valid historical entity by
  reapplying a creation-time future-date check to an unchanged start time.
- Fetch enough parent context to evaluate catalog rules. Ad validation can require the
  parent ad set's format, platforms, and dates as well as the campaign objective or
  delivery goal group.
- Fetch referenced assets when rules depend on asset type, status, duration, audio
  tracks, or archive state.

Do not manufacture a pass result for fields or conditions that the catalog does not
address.

## 4. Handle Static and Runtime Rules Honestly

Classify applicable rules while validating:

1. **Static rules** can be evaluated from the final entity and fetched parent context.
   Enforce these before the mutation.
2. **Resolvable runtime rules** require a read-only API check. Use the appropriate
   endpoint when the inputs are available, for example audience or bid estimates,
   reserved pricing, asset lookup, or reporting data needed for a budget decrease.
3. **Server-only rules** depend on state the public API does not expose, such as an
   internal exemption or cooldown. Do not label these as passed. Apply every known
   prerequisite, allow the mutation endpoint to perform the authoritative check, and
   report any rejection normally.

If a known value violates a rule, do not send it. If a runtime condition cannot be
proved locally, do not turn that uncertainty into a user confirmation gate or claim
that the condition passed.

## 5. Minimize User Interruptions

- If an assistant-inferred value or default violates the catalog, replace it with a
  compliant value and disclose the adjustment in the existing plan or change summary.
- If a value explicitly chosen by the user violates the catalog, explain the exact
  rule, recommend compliant alternatives, and ask one focused question. Revalidate the
  revised value.
- Ask only when there is no safe compliant choice or the alternatives materially change
  the user's intent.
- Do not print per-field pass checklists or add a separate confirmation for validation.
  When the workflow already presents a plan or change summary, add one compact line such
  as `Ad product validation: static AUCTION rules passed` and mention only material
  adjustments or unresolved server-only checks.
- Validation never replaces an existing confirmation required by `auto_execute`, bulk
  changes, or draft publishing.

For draft hierarchies, perform this catalog preflight before creating or editing drafts,
then run the draft campaign `VALIDATE` action as the authoritative hierarchy check.
Publishing remains the only mandatory extra confirmation.
