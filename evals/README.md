# Evals

Behavior and language checks for the plugin's skills, run with
[`claude plugin eval`](https://code.claude.com/docs/en/plugin-evals). No case calls
the Ads API or needs Ads API credentials. Runs still need Claude Code
authentication, because the agent and the judge are real model calls, and network
access to download the OpenAPI document.

## Running

```bash
# Every case, run from the repository root. Use the JUDGE_MODEL and MAX_COST_USD
# values set at the top of evals/run-in-docker.sh.
claude plugin eval . --ablation none --runs 3 --scaffold --allow-tools Bash \
  --judge-model <JUDGE_MODEL> --max-cost-usd <MAX_COST_USD> --no-publish
```

Add `--tag <tag>` or `--case <ID>` to run fewer cases. Each case costs well under
a dollar at three runs; `report.html` shows the actual cost per case, and
`--max-cost-usd` stops a run that goes over the cap. `--runs 1` is a cheaper first look. Scores vary between
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
adds the options the cases need, including the judge model and cost cap, unless
you pass them (the list is in the script), and writes results to `evals/results/`. It prints the report's path as
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

## Keep the run looking real

Nothing the agent under test can see should mark the run as a test. An agent that
can tell it's being evaluated may not behave the way it would for a real user, and
then the score measures the wrong thing. This rule explains several choices that
otherwise look odd:

- The dummy settings file has a realistic-looking token and expiry, not a
  placeholder.
- Campaigns and other fixture data use real-sounding names.
- Fixtures sit under `.git/ads-cache`, not in a visible folder.
- In replay mode, `scripts/api-request.sh` fails with the same "Run the configure
  skill first" error a real user would see, and a request with no fixture gets the
  real API's 404 body.

It also means explanations belong in this README, never in files the scaffold
copies into the workspace, such as `fixtures/settings.local.md` or anything under
`api/`.

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
- `fixtures/dry-run.sh` records a session against a case's fixtures, and
  `fixtures/trim-transcript.py` turns it into the case's `history.jsonl`. It drops
  the skill-loading step, so start those prompts with the skill's slash command and
  each run loads the current `SKILL.md`.
- `shared-graders/`: checks used by more than one case. A case links to one with a
  relative symlink under its own file name (`graders/date-range.md ->
  ../../../shared-graders/date-range.md`), so editing the shared file changes every
  case that uses it. Add one when a second case needs an identical check.
- `smoke/<ID>/`: the smoke-test cases, one per expected behavior, named by case ID.

Fixture data is invented, and no IDs in it belong to real accounts.

## Adding a case

Using `smoke/P1-01/` as the template:

1. Copy the folder to `smoke/<ID>/` and set `name` and `description` in
   `case.yaml`.
2. Write the user's message in `execution.prompt`. Phrase it the way an advertiser
   would, with nothing that hints at a test.
3. Replace the files in `api/` with the responses this case needs. Name each one by
   the key described in [How API calls are replayed](#how-api-calls-are-replayed);
   anything not in `api/` falls back to `fixtures/api/default/`. Record real
   responses where you can, then strip anything identifying.
4. Add the checks only this case uses under `graders:` in `case.yaml`.
5. Link the shared checks it needs from `graders/`, for example
   `ln -s ../../../shared-graders/no-write-requests.md graders/no-mutation.md`.
   Keep `scaffold.sh` as a regular file, not a symlink.
6. Run it with `--case <ID> --runs 1`, then confirm with three runs.

## Debugging a failing case

- Open `report.html` in the run's results folder to see which checks failed in
  which runs.
- A score of 0.00 at $0.00 means the case never started. The error is in the
  report's notes; the Docker Desktop message above is the usual one on a Mac.
- Add `--keep-temp` to keep each run's workspace. Its `.claude/.api-requests.log`
  lists every request the agent sent, which shows whether it called the endpoints
  you expected. With `run-in-docker.sh`, kept workspaces go to
  `~/.cache/ads-plugin-evals/tmp` (or `ADS_EVAL_TMP`).
- A request the agent sent but the case has no fixture for gets a 404. If the agent
  then gives up or asks the user something, add the missing fixture.
- If the scaffold fails, check the OpenAPI download first: a failed download fails
  every case.
- `--verbose` logs per-message trace events to the debug log.
