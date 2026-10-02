# Evals

Offline behavior and language checks for the plugin's skills, run with
[`claude plugin eval`](https://code.claude.com/docs/en/plugin-evals). No case calls
the Ads API or needs credentials.

## Running

```bash
# Cases that need no API access (saved conversations, refusals)
claude plugin eval . --tag language --ablation none --runs 3

# Cases where the skill calls the API against replayed fixtures
claude plugin eval . --tag smoke --ablation none --runs 3 \
  --scaffold --allow-tools Bash --judge-model claude-sonnet-5
```

Use `--ablation none`: without the plugin there is no API wrapper, so the
no-plugin baseline only measures failure. Compare skill versions by running the
same cases on two branches.

Cases that grant Bash cannot run on a Mac with Docker Desktop installed
([anthropics/claude-code#94308](https://github.com/anthropics/claude-code/issues/94308)).
Run them in the Linux container instead:

```bash
claude setup-token                      # once; save the token in evals/docker/.token
evals/run-in-docker.sh --tag smoke --runs 3
evals/run-in-docker.sh --case P1-01 --runs 1
```

`run-in-docker.sh` builds the image on first use (`ADS_EVAL_REBUILD=1` rebuilds it),
adds the usual options (`--ablation none --scaffold --allow-tools Bash --trust-plugin
--no-publish --judge-model claude-sonnet-5 --max-cost-usd 20`) unless you pass them,
and writes results to `evals/results/`. `evals/docker/.token` is gitignored; you can
also pass `CLAUDE_CODE_OAUTH_TOKEN` or `ANTHROPIC_API_KEY` in the environment.

## How API calls are replayed

When `EVAL_ADS_API_FIXTURES` is set, `scripts/api-request.sh` answers from fixture
files instead of calling the API, and appends each request to
`.claude/.api-requests.log` in the workspace so graders can check what was sent.

Each case's scaffold copies its fixtures to `/tmp/spotify-ads-cache/<case>`, outside
the workspace. When fixtures sat in the workspace, the agent under test sometimes
listed the folder and read them directly instead of calling the API, so keep
fixtures, settings, and names free of anything that marks the run as a test.
`scripts/fetch-openapi-schema.sh` serves the checked-in schema snapshot.

A fixture is `<METHOD>__<path>.http`: the first line is the HTTP status, the rest is
the response body. In the path, `/` becomes `__`, the ad account ID becomes
`{ad_account_id}`, other UUIDs become `{id}`, and the query string is dropped.
`<key>.<n>.http` answers the nth call to the same key, and
`<key>.match-<WORD>.http` answers when the request path, including its query, or
the body contains `WORD`. Use it for requests that share a key, such as draft
`VALIDATE` and `PUBLISH`, or a list filtered by query. A request with no fixture gets a plain 404.

## Recording real responses

Set `EVAL_ADS_API_RECORD=<dir>` and run a workflow against a test account to save
each real response as a fixture under the same key. Recording only sends GET
requests. Any other method is refused unless `EVAL_ADS_API_RECORD_ALLOW_WRITES=1`
is also set, so a recording run can't change the account. Remove IDs, names, and
anything personal from recorded files before committing them.

## Layout

- `fixtures/`: the dummy settings files, the shared scaffold, default API responses,
  scenario overrides, and the OpenAPI snapshot.
- `fixtures/trim-transcript.py`: turns a recorded session into a case's
  `history.jsonl`. It drops the skill-loading step, so start those prompts with the
  skill's slash command and each run loads the current `SKILL.md`.
- `smoke/<ID>/`: cases from the design team's smoke-test sheet, named by row ID.
  Each has its own `api/` fixtures layered over the defaults. `smoke/generate.py`
  holds the rows and writes their cases; edit a row there and rerun it rather than
  editing the generated files.
- `safety/`: the safety scenarios from `tests/test-scenarios.md` (18, 19, 24, 30,
  34). Each checks the request log for the action that must not happen before
  confirmation.
- `campaigns/`, `build-campaign/`: earlier example cases.

Fixture data is invented, and no IDs in it belong to real accounts.
