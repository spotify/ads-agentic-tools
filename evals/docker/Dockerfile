# Linux image for running the plugin evals. On macOS with Docker Desktop installed,
# `claude plugin eval` refuses any case that grants Bash
# (anthropics/claude-code#94308); inside this container there is no ~/.docker, and
# bubblewrap provides the Bash sandbox. Built and run by evals/run-in-docker.sh.
FROM node:22-bookworm-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bubblewrap socat git ca-certificates curl jq python3 python3-yaml uuid-runtime \
  && rm -rf /var/lib/apt/lists/*

ARG CLAUDE_CODE_VERSION=latest
RUN npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" && claude --version

# Claude Code's sandbox and trust prompts expect a normal, non-root user.
RUN useradd --create-home --shell /bin/bash runner
USER runner
WORKDIR /plugin
ENV CI=true

ENTRYPOINT ["claude", "plugin", "eval", "/plugin"]
