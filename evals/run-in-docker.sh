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
# Options added unless you pass them yourself are the `has ... || ARGS+=` lines
# below. JUDGE_MODEL and MAX_COST_USD are the only place the judge model and
# cost cap are set; the README points here. Results land in evals/results/ in
# this checkout.
set -euo pipefail

JUDGE_MODEL=claude-sonnet-5
MAX_COST_USD=20

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
has --judge-model "$@"  || ARGS+=(--judge-model "$JUDGE_MODEL")
has --max-cost-usd "$@" || ARGS+=(--max-cost-usd "$MAX_COST_USD")

# Claude Code's Bash sandbox (bubblewrap) needs user namespaces, which Docker's
# default seccomp profile blocks, and must mount /proc in a new PID namespace,
# which Docker's masked /proc paths block. These only loosen this throwaway
# container's own confinement. A tmpfs over each settings folder in this
# checkout (.claude, .codex, .agents) keeps real settings files with live
# credentials out of the container, and one over /plugin/evals/docker does the
# same for the saved token. Credentials are passed by name (-e NAME), so their
# values don't appear in the docker command line.
#
# Kept run sandboxes (--keep-temp) and traces go to a host folder outside the
# plugin: plugin eval refuses to load cases while they sit inside the plugin dir.
EVAL_TMP="${ADS_EVAL_TMP:-$HOME/.cache/ads-plugin-evals/tmp}"
mkdir -p "$EVAL_TMP"
RUN_ARGS=(--mount type=tmpfs,destination=/plugin/evals/docker)
for dir in .claude .codex .agents; do
  [ -d "$REPO/$dir" ] && RUN_ARGS+=(--mount "type=tmpfs,destination=/plugin/$dir")
done
for var in CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY; do
  [ -n "${!var:-}" ] && { export "${var?}"; RUN_ARGS+=(-e "$var"); }
done
docker run --rm -i \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  -e TMPDIR=/evaltmp \
  -v "$EVAL_TMP:/evaltmp" \
  -v "$REPO:/plugin" \
  "${RUN_ARGS[@]}" \
  "$IMAGE" "${ARGS[@]}"
