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
Run those in CI or on a machine without Docker Desktop.

## How API calls are replayed

When `EVAL_ADS_API_FIXTURES` is set, `scripts/api-request.sh` answers from fixture
files instead of calling the API, and appends each request to
`ads-api-requests.log` in the workspace so graders can check what was sent.
`scripts/fetch-openapi-schema.sh` serves the checked-in schema snapshot.

A fixture is `<METHOD>__<path>.http`: the first line is the HTTP status, the rest is
the response body. In the path, `/` becomes `__`, the ad account ID becomes
`{ad_account_id}`, other UUIDs become `{id}`, and the query string is dropped.
`<key>.<n>.http` answers the nth call to the same key. A request with no fixture
gets a plain 404.

## Layout

- `fixtures/`: the dummy settings files, the shared scaffold, default API responses,
  scenario overrides, and the OpenAPI snapshot.
- `fixtures/trim-transcript.py`: turns a recorded session into a case's
  `history.jsonl`. It drops the skill-loading step, so start those prompts with the
  skill's slash command and each run loads the current `SKILL.md`.
- `smoke/<ID>/`: cases from the design team's smoke-test sheet, named by row ID.
  Each has its own `api/` fixtures layered over the defaults.
- `campaigns/`, `build-campaign/`: earlier example cases.

Fixture data is invented, and no IDs in it belong to real accounts.
