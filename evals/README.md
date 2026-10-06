# Evals

Offline behavior and language checks for the plugin's skills, run with
[`claude plugin eval`](https://code.claude.com/docs/en/plugin-evals). No case calls
the Ads API or needs credentials.

## Running

```bash
# Every case, run from the repository root
claude plugin eval . --ablation none --runs 3 \
  --scaffold --allow-tools Bash --judge-model claude-sonnet-5 --no-publish
```

Add `--tag <tag>` or `--case <ID>` to run fewer cases. Each case costs roughly
$0.40 at three runs, and `--runs 1` is a cheaper first look. Scores vary between
runs, so confirm a change with three runs before trusting it. A full run takes
several minutes, so start it in the background. Results, including `report.html`,
go to a new folder under `evals/results/`.

Use `--ablation none`: without the plugin there is no API wrapper, so the
no-plugin baseline only measures failure. Compare skill versions by running the
same cases on two branches.

On a Mac with Docker Desktop installed, `claude plugin eval` can't give an eval
access to Bash, so it won't run the cases that need it
([anthropics/claude-code#94308](https://github.com/anthropics/claude-code/issues/94308)).
If that happens, run the suite in the Linux container instead:

```bash
claude setup-token                      # once; save the token in evals/docker/.token
evals/run-in-docker.sh --runs 3
evals/run-in-docker.sh --case P1-01 --runs 1
```

`run-in-docker.sh` builds the image on first use (`ADS_EVAL_REBUILD=1` rebuilds it),
adds the usual options (`--ablation none --scaffold --allow-tools Bash --trust-plugin
--no-publish --judge-model claude-sonnet-5 --max-cost-usd 20`) unless you pass them,
and writes results to `evals/results/`. It prints the report's path as
`/plugin/evals/results/...`, which is `evals/results/...` in this checkout.
`evals/docker/.token` is gitignored; you can also pass `CLAUDE_CODE_OAUTH_TOKEN`
or `ANTHROPIC_API_KEY` in the environment.

## Example Natural Language Prompt

To run the suite from a Claude Code session in this repository, ask:

> Read `evals/README.md` and follow its instructions to run the eval suite. When it
> finishes, open the new `report.html` in my browser, then tell me which cases
> scored below 1.0 and which checks failed in each.

## How API calls are replayed

When `EVAL_ADS_API_FIXTURES` is set, `scripts/api-request.sh` answers from fixture
files instead of calling the API, and appends each request to
`.claude/.api-requests.log` in the workspace so graders can check what was sent.

Each case's scaffold makes the workspace a git repository and copies its fixtures
to `.git/ads-cache`. When fixtures sat in a visible folder, the agent under test
sometimes listed the workspace and read them directly instead of calling the API.
They can't go outside the workspace either, because eval runs can't read `/tmp`.
Keep fixtures, settings, and names free of anything that marks the run as a test.
Each case's scaffold downloads the current public OpenAPI document into the
workspace, and `scripts/fetch-openapi-schema.sh` serves it from there, so a case
fails if the download does.

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

Each case is a folder holding:

- `case.yaml`: the prompt, run settings, and the checks only that case uses.
- `scaffold.sh`: runs `fixtures/scaffold.sh` with a settings file and the case's
  `api/` folder. It can't be a symlink: the runner resolves the link and gives the
  script no other way to find its case.
- `api/`: the case's API responses, layered over `fixtures/api/default/`.
- `graders/`: symlinks to the shared checks the case uses.

The suite is organized as:

- `fixtures/`: the dummy settings files, the shared scaffold, and default API responses.
- `shared-graders/`: checks used by more than one case. A case links to one with a
  relative symlink under its own file name (`graders/date-range.md ->
  ../../../shared-graders/date-range.md`), so editing the shared file changes every
  case that uses it. Add one when a second case needs an identical check.
- `smoke/<ID>/`: the smoke-test cases, one per expected behavior, named by case ID.

Fixture data is invented, and no IDs in it belong to real accounts.
