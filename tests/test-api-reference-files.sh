#!/bin/bash
# Regression checks that static API reference copies stay removed and links resolve.
# Run: bash tests/test-api-reference-files.sh

set -uo pipefail

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REFS="$REPO_ROOT/skills/api-reference/references"
fail=0

for f in endpoints.md schemas.md enums.md; do
  if [ -e "$REFS/$f" ]; then echo "FAIL: $f should not exist"; fail=1; fi
done
for f in api-behaviors.md live-openapi.md ad-product-validation.md create-retry-safety.md; do
  if [ ! -f "$REFS/$f" ]; then echo "FAIL: missing $f"; fail=1; fi
done

stale=$(git -C "$REPO_ROOT" grep -n -E "references/(endpoints|enums|schemas)\.md|\b(endpoints|enums|schemas)\.md" -- . ':!CHANGELOG.md' ':!tests/test-api-reference-files.sh')
if [ -n "$stale" ]; then echo "FAIL: stale references:"; echo "$stale"; fail=1; fi

for f in "$REPO_ROOT"/skills/*/SKILL.md; do
  if ! grep -qF 'Before the first Ads API v3 call, read and follow `$PLUGIN_ROOT/skills/api-reference/references/live-openapi.md`.' "$f"; then
    case "$f" in */configure/*|*/api-reference/*) continue ;; esac
    echo "FAIL: $f lacks live-openapi.md preflight"; fail=1
  fi
done

BEHAVIORS='skills/api-reference/references/api-behaviors.md'
for k in ads build-campaign drafts campaigns clone bulk report dashboard monitor export campaign-strategy media-plan-to-draft; do
  if ! grep -qF "Also read \`\$PLUGIN_ROOT/$BEHAVIORS\`" "$REPO_ROOT/skills/$k/SKILL.md"; then
    echo "FAIL: skills/$k/SKILL.md lacks api-behaviors.md pointer"; fail=1
  fi
done
if ! grep -qF "Also read \`\$PLUGIN_ROOT/$BEHAVIORS\`" "$REPO_ROOT/agents/spotify-ads-request-builder.md"; then
  echo "FAIL: request-builder agent lacks api-behaviors.md pointer"; fail=1
fi
grep -qF '`references/api-behaviors.md`' "$REPO_ROOT/skills/api-reference/SKILL.md" || { echo "FAIL: api-reference SKILL.md lacks api-behaviors.md pointer"; fail=1; }

# Every $PLUGIN_ROOT/skills/api-reference/references/*.md path mentioned anywhere must resolve.
for ref in $(git -C "$REPO_ROOT" grep -h -o -E 'skills/api-reference/references/[A-Za-z0-9_-]+\.md' -- skills agents AGENTS.md ':!CHANGELOG.md' | sort -u) "$BEHAVIORS"; do
  [ -f "$REPO_ROOT/$ref" ] || { echo "FAIL: unresolved $ref"; fail=1; }
done

# Inline critical rules must appear verbatim in each high-risk file.
for f in skills/api-reference/SKILL.md skills/build-campaign/SKILL.md skills/ads/SKILL.md skills/drafts/SKILL.md agents/spotify-ads-request-builder.md; do
  for rule in \
    'Send only fields the live spec defines for the operation; include every field it marks required' \
    'Set `placements` when creating an ad set and on every audience estimate, using only values the ad product catalog allows' \
    'Never resend a request body that was rejected with a 4xx unchanged; fix it from the error first.' \
    'Before VALIDATE/PUBLISH, refetch `draft_hierarchy_version` from the draft campaign.'; do
    grep -qF -- "$rule" "$REPO_ROOT/$f" || { echo "FAIL: $f missing critical rule: $rule"; fail=1; }
  done
done

[ "$fail" -eq 0 ] && echo "PASS: api-reference files" || exit 1
