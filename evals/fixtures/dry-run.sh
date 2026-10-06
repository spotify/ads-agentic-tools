#!/bin/bash
# Run one eval case's prompt in a normal headless Claude session against its
# replay fixtures, then print the reply and the request log. Not graded: use it to
# find missing fixtures, or where `claude plugin eval` can't grant Bash.
#
# Usage: evals/fixtures/dry-run.sh <case-dir> [prompt]
#   The prompt defaults to the case's execution.prompt in case.yaml.
#   Set DRY_RUN_KEEP=1 to keep the workspace and print its path.
set -uo pipefail

CASE="$(CDPATH= cd -- "$1" && pwd)"
PLUGIN_ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
PROMPT="${2:-$(awk '/^  prompt: \|$/ {p = 1; next} p && /^    / {print substr($0, 5); next} {p = 0}' "$CASE/case.yaml")}"

WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/project.XXXXXX")"
[ "${DRY_RUN_KEEP:-}" = "1" ] || trap 'rm -rf "$WORKSPACE"' EXIT
cd "$WORKSPACE" || exit 1

if [ -x "$CASE/scaffold.sh" ]; then
  bash "$CASE/scaffold.sh" >/dev/null
else
  bash "$PLUGIN_ROOT/evals/fixtures/scaffold.sh" >/dev/null
fi

SESSION_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
CLAUDE_PROJECT_DIR="$WORKSPACE" EVAL_ADS_API_FIXTURES=.git/ads-cache claude -p "$PROMPT" \
  --plugin-dir "$PLUGIN_ROOT" --setting-sources project --session-id "$SESSION_ID" \
  --allowedTools "Bash,Read,Glob,Grep,Skill" --max-turns 30 < /dev/null

echo
echo "--- requests"
cut -c1-200 .claude/.api-requests.log
echo "--- session $SESSION_ID"
[ "${DRY_RUN_KEEP:-}" = "1" ] && echo "--- workspace $WORKSPACE"
