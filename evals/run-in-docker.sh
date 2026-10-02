#!/bin/bash
# Run `claude plugin eval` against this checkout inside a Linux container.
#
# Usage: evals/run-in-docker.sh [plugin eval options...]
#   evals/run-in-docker.sh --tag safety --runs 3
#   evals/run-in-docker.sh --case P1-01 --runs 1
#
# Authentication: set CLAUDE_CODE_OAUTH_TOKEN (create one with `claude setup-token`)
# or ANTHROPIC_API_KEY, or put the OAuth token in evals/docker/.token (gitignored).
#
# Defaults added unless you pass them yourself: --ablation none, --scaffold,
# --allow-tools Bash, --trust-plugin, --no-publish, --judge-model claude-sonnet-5,
# --max-cost-usd 20. Results land in evals/results/ in this checkout.
set -euo pipefail

REPO="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
IMAGE="${ADS_EVAL_IMAGE:-spotify-ads-plugin-evals}"
TOKEN_FILE="$REPO/evals/docker/.token"

if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -f "$TOKEN_FILE" ]; then
  CLAUDE_CODE_OAUTH_TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
fi
if [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] && [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "ERROR: set CLAUDE_CODE_OAUTH_TOKEN (from \`claude setup-token\`) or ANTHROPIC_API_KEY," >&2
  echo "       or save the token in evals/docker/.token." >&2
  exit 1
fi

if [ "${ADS_EVAL_REBUILD:-}" = "1" ] || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  docker build -t "$IMAGE" "$REPO/evals/docker"
fi

has() { local flag="$1"; shift; for a in "$@"; do [ "$a" = "$flag" ] && return 0; done; return 1; }
ARGS=("$@")
has --ablation "$@"     || ARGS+=(--ablation none)
has --scaffold "$@"     || ARGS+=(--scaffold)
has --allow-tools "$@"  || ARGS+=(--allow-tools Bash)
has --trust-plugin "$@" || ARGS+=(--trust-plugin)
has --no-publish "$@"   || ARGS+=(--no-publish)
has --judge-model "$@"  || ARGS+=(--judge-model claude-sonnet-5)
has --max-cost-usd "$@" || ARGS+=(--max-cost-usd 20)

# bubblewrap needs user namespaces, which Docker's default seccomp profile blocks.
docker run --rm -i \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  -e CLAUDE_CODE_OAUTH_TOKEN="${CLAUDE_CODE_OAUTH_TOKEN:-}" \
  -e ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}" \
  -v "$REPO:/plugin" \
  "$IMAGE" "${ARGS[@]}"
