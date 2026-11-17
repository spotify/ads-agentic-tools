# How to Contribute

We'd love to get patches from you!

## Getting Started

Look for issues labeled [`good first issue`](https://github.com/spotify/ads-agentic-tools/labels/good%20first%20issue) — these are scoped problems that are great for first-time contributors.

## Building the Project

This is a Codex, Claude Code, and Antigravity CLI plugin package made mostly of markdown files. There is no build step, no package manager, and no compiled code.

To run the plugin locally:

1. Clone the repository:
   ```bash
   git clone https://github.com/spotify/ads-agentic-tools.git
   ```

2. Register or launch the plugin locally.

   For Codex:
   ```bash
   codex plugin marketplace add /path/to/ads-agentic-tools
   ```

   For Claude Code:
   ```bash
   claude --plugin-dir /path/to/ads-agentic-tools
   ```

   For Antigravity CLI:
   ```bash
   agy plugin link /path/to/ads-agentic-tools
   ```

3. Configure credentials:
   ```
   /spotify-ads-api:configure
   ```
   (`/configure` on Antigravity)

## Workflow

We follow the [GitHub Flow Workflow](https://guides.github.com/introduction/flow/)

1.  Fork the project
1.  Check out the `main` branch
1.  Create a feature branch
1.  Write and review your changes
1.  From your branch, make a pull request against `main`
1.  Work with repo maintainers to get your change reviewed
1.  Wait for your change to be merged
1.  Delete your feature branch

## Testing

See [`tests/README.md`](tests/README.md) for the full test guide.

### Regression tests

The regression suites run offline, with no credentials, network access, or API
calls, and exit non-zero on failure. Run the relevant ones after changing
`hooks/`, `scripts/`, `skills/configure/scripts/`, skill examples, or marketplace
metadata:

```bash
bash tests/test-check-token.sh          # hooks/check-token.sh and attribution
bash tests/test-api-request.sh          # scripts/api-request.sh
bash tests/test-openapi-fetch.sh        # scripts/fetch-openapi-schema.sh and per-skill preflight
bash tests/test-openapi-tool.sh         # openapi_tool.py, openapi-op.sh, pre-send validation
bash tests/test-audience-estimates.sh   # audience estimate examples
bash tests/test-api-reference-files.sh  # api-reference file layout and links
bash tests/test-marketplace-metadata.sh # manifests, marketplaces, version alignment
bash tests/test-pkce-runtime-guard.sh   # no secret-based OAuth paths
python3 tests/test-oauth-pkce.py        # PKCE OAuth helpers
```

### Evals

Skill behavior and language are checked with `claude plugin eval`, using
recorded API responses instead of the live API. See
[`evals/README.md`](evals/README.md) for how to run them, including the Docker
runner.

### Manual checks

Before submitting a pull request:

- Verify your changes work against the Spotify Ads API on at least one supported platform (Codex, Claude Code, or Antigravity CLI)
- Confirm that existing skills (`/spotify-ads-api:campaigns`, `/spotify-ads-api:ads`, etc.) still function correctly
- If adding a new skill, include a `SKILL.md` following the patterns in existing skill directories
- If touching `hooks/`, note there are three per-platform hook configs: `hooks.json` at plugin root (Antigravity CLI and 2.0, `PreToolUse`), `.claude-plugin/hooks.json` (Claude), and `.codex-plugin/hooks.json` (Codex) — all calling `check-token.sh`. Test the token-refresh hook on all three platforms

## Style

- Most source files are markdown (`.md`); helper scripts are bash and standard-library Python with no third-party dependencies. Follow the structure and conventions of existing files.
- Skills live in `skills/<skill-name>/SKILL.md`.
- Express Ads API requests with the shared `api()` helper, as described in the execution pattern in `AGENTS.md`, rather than raw `curl`.
- Add an entry under `[Unreleased]` in `CHANGELOG.md` for user-visible changes.

## Issues

When creating an issue please try to ahere to the following format:

    One line summary of the issue (less than 72 characters)

    ### Expected behavior

    As concisely as possible, describe the expected behavior.

    ### Actual behavior

    As concisely as possible, describe the observed behavior.

    ### Steps to reproduce the behavior

    List all relevant steps to reproduce the observed behavior.

## Pull Requests

Comments should be formatted to a width no greater than 80 columns.

Files should be exempt of trailing spaces.

We adhere to a specific format for commit messages. Please write your commit
messages along these guidelines. Please keep the line width no greater than 80
columns (You can use `fmt -n -p -w 80` to accomplish this).

    One line description of your change (less than 72 characters)

    Problem

    Explain the context and why you're making that change.  What is the problem
    you're trying to solve? In some cases there is not a problem and this can be
    thought of being the motivation for your change.

    Solution

    Describe the modifications you've done.

    Result

    What will change as a result of your pull request? Note that sometimes this
    section is unnecessary because it is self-explanatory based on the solution.

Some important notes regarding the summary line:

* Describe what was done; not the result
* Use the active voice
* Use the present tense
* Capitalize properly
* Do not end in a period — this is a title/subject

## Code Review

When you submit a pull request on GitHub, it will be reviewed by the project
community (both inside and outside of Spotify), and once the changes are
approved, your commits will be brought into Spotify's internal system for
additional testing. Once the changes are merged internally, they will be pushed
back to GitHub with the next sync.

This process means that the pull request will not be merged in the usual way.
Instead a member of the project team will post a message in the pull request
thread when your changes have made their way back to GitHub, and the pull
request will be closed.
The changes in the pull request will be collapsed into a single commit, but the
authorship metadata will be preserved.

## Documentation

We also welcome improvements to the project documentation or to the existing
docs. Please file an [issue](https://github.com/spotify/ads-agentic-tools/issues/new).

# License

By contributing your code, you agree to license your contribution under the
terms of the [LICENSE](LICENSE)

# Code of Conduct

Read our [Code of Conduct](CODE_OF_CONDUCT.md) for the project.
