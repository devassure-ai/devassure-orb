# DevAssure Orb

> DevAssure O2 automatically generates and runs end-to-end browser tests for your CircleCI pipelines.

**DevAssure O2 reads your change set, generates the right tests, and runs them before merge. No scripts. No maintenance.**

CircleCI orb for running [@devassure/cli](https://www.npmjs.com/package/@devassure/cli) commands in CI.

## How it works

> reads code diff -> maps blast radius -> generates tests -> executes

1. Add the `devassure/devassure` orb to your CircleCI workflow.
2. The orb invokes the DevAssure O2 agent, which reads and understands the change.
3. It generates extensive natural-language end-to-end UI tests for impacted areas.
4. It runs those tests in browsers.
5. It reports outcomes in CircleCI test results and artifacts.

## Before vs After DevAssure O2

**Before:**  
❌ Write & maintain test scripts  
❌ Run full regression suite  
❌ Miss edge cases  

**After DevAssure O2:**  
✅ Tests generated from PR diff  
✅ Only impacted areas tested  
✅ Bugs caught before merge  

Learn more about DevAssure O2 [here](https://devassure.io).

## What this orb does

- Validates Node.js runtime (requires Node 20+).
- Installs `@devassure/cli@1` globally.
- Prints `devassure version`.
- Resolves token from:
  - job/command parameter `token`, or
  - `DEVASSURE_TOKEN` environment variable.
- Runs `devassure <command>` with command-specific arguments.
- For `test` and `run`:
  - prints `devassure summary --last`
  - validates score threshold (`minimum_score`, default `75`)
  - runs `archive-report` and stores artifacts
  - publishes JUnit results to CircleCI **Tests** tab

## Create a DevAssure token

1. Log in to [https://app.devassure.io](https://app.devassure.io) or sign up at [https://app.devassure.io/sign_up](https://app.devassure.io/sign_up).
2. Generate an API token from account settings.
3. Add it in CircleCI Project Settings or Contexts as `DEVASSURE_TOKEN`.

## Prerequisites

- Linux or macOS CircleCI executors with Node 20+.
- `checkout` enabled for branch-aware `test` flows (enabled by default via `checkout: true`).
- Branch refs available when using `source` and `target` comparisons.

## Usage

### Default (test pull request / branch)

```yaml
version: 2.1
orbs:
  devassure: devassure/devassure@1

workflows:
  validate:
    jobs:
      - devassure/devassure:
          token: $DEVASSURE_TOKEN
```

### Test command with branch refs and score gate

```yaml
version: 2.1
orbs:
  devassure: devassure/devassure@1

workflows:
  validate:
    jobs:
      - devassure/devassure:
          token: $DEVASSURE_TOKEN
          command: test
          source: << pipeline.git.branch >>
          target: main
          default_branch: main
          commit_id: << pipeline.git.revision >>
          url: https://example.com
          environment: staging
          workers: 2
          minimum_score: 80
          headless: true
```

### Run command with filters

```yaml
version: 2.1
orbs:
  devassure: devassure/devassure@1

workflows:
  runFilteredTests:
    jobs:
      - devassure/devassure:
          token: $DEVASSURE_TOKEN
          command: run
          path: e2e
          filter: smoke
          query: "login flow"
          tag: nightly
          priority: high
          folder: reports
          url: https://example.com
          environment: qa
          workers: 2
          headless: false
```

### Summary command

```yaml
- devassure/devassure:
    token: $DEVASSURE_TOKEN
    command: summary
    session_id: sess_123
```

If `session_id` is not set, the orb runs `devassure summary --last`.

### Archive command

```yaml
- devassure/devassure:
    token: $DEVASSURE_TOKEN
    command: archive
    session_id: sess_123
```

If `session_id` is not set, the orb runs `devassure archive-report --last`.

## Job Parameters (`devassure/devassure`)

| Parameter | Default | Description |
| --- | --- | --- |
| `checkout` | `true` | Runs CircleCI `checkout` step before DevAssure execution |
| `executor_tag` | `24.4` | `cimg/node` image tag used by the orb's default executor |
| `command` | `test` | DevAssure command to execute: `setup`, `test`, `run`, `summary`, `archive`, or `archive-report` |
| `token` | _empty_ | DevAssure API token. If empty, falls back to `DEVASSURE_TOKEN` environment variable |
| `path` | _empty_ | Relative project path to test/run (useful in monorepos) |
| `source` | _empty_ | Source branch for `test` command scope |
| `target` | _empty_ | Target branch for `test` command scope |
| `default_branch` | _empty_ | Default branch fallback used by `test` when `target` is not provided |
| `commit_id` | _empty_ | Commit SHA for `test` command scope |
| `filter` | _empty_ | Filter expression for selecting tests in `run` command |
| `query` | _empty_ | Query string for selecting tests in `run` command |
| `tag` | _empty_ | Tag selector for `run` command |
| `priority` | _empty_ | Priority selector for `run` command |
| `folder` | _empty_ | Folder selector for `run` command |
| `url` | _empty_ | Application URL under test for `test` and `run` commands |
| `headless` | `true` | Headless browser mode flag for `test` and `run` |
| `session_id` | _empty_ | Session ID for `summary` or `archive`/`archive-report` (uses latest session when empty) |
| `archive` | `true` | For `test`/`run`, set to `false` to skip `archive-report --last` |
| `minimum_score` | `75` | Minimum score threshold for `test`/`run`; accepts positive integers and fails when summary score is below this value |
| `workers` | `0` | Worker count for `test`/`run`; when set above `0`, `--workers` is passed to the CLI. If value is `0`, project default is used |
| `environment` | _empty_ | Environment name passed to `test`/`run` (for example `staging`, `qa`, or `production`) |
| `verbose` | `false` | Enables `--verbose` logging |
| `debug` | `false` | Enables `--debug` logging |

## Command parameter mapping

The orb forwards supported values in this format:

`--<arg-name>=<arg-value>`

- `setup`: none
- `test`: `path`, `source`, `target`, `commit_id`, `url`, `workers`, `environment`, `headless` (`headless` defaults to `true` and is always passed)
- `run`: `path`, `filter`, `query`, `tag`, `priority`, `folder`, `url`, `workers`, `environment`, `headless` (`headless` defaults to `true` and is always passed)
- `summary`: `session_id` when provided, else `--last` (never both)
- `archive` / `archive-report`: `session_id` when provided, else `--last` (never both)

For `test` and `run`, score is validated using `devassure summary --last`:

- If `minimum_score` is non-numeric or `<= 0`, validation is skipped.
- If `score` is missing or `N/A`, the job fails.
- If `score` is lower than `minimum_score`, the job fails.

## Branch safety behavior (`command: test`)

- Verifies `.git` exists and current HEAD is attached to a branch.
- Resolves default branch using:
  1. `default_branch` parameter
  2. `origin/HEAD` from remote metadata
  3. fallback to `main` (or `master` if available remotely)
- Fetches target or default branch ref from `origin`.
- If `source` is provided, fetches source ref and checks it out.

## Artifacts and score validation

- Artifacts are stored under `.devassure-artifacts`.
- If archive runs successfully, `.devassure-artifacts/archive_path.txt` contains the generated path.
- Score gate runs for `test` and `run` when `minimum_score` is a valid positive integer.
- The job fails when score is missing, `N/A`, non-numeric, or below the threshold.

## Runner sizing recommendation

- Baseline for parallel browser execution: `4 vCPU / 16 GB RAM`.
- Increase machine size as you increase `workers`.

## FAQs

### How does minimum score work?

The minimum score is the lowest score that still passes the job. The default is `75`. If the score is below minimum, the job fails. If the score is equal to or above minimum, the job passes. Set `minimum_score` to `0` to disable validation.

### How are credits consumed?

Credits are consumed based on browser interactions and test complexity. Per-run usage is available at [https://app.devassure.io/usage](https://app.devassure.io/usage).

### How can I view the complete report?

The complete report is stored as CircleCI artifacts and can be opened using the DevAssure [CLI](https://www.npmjs.com/package/@devassure/cli) or DevAssure [VS Code extension](https://marketplace.visualstudio.com/items?itemName=devassure.devassure-vscode).

### Can I invoke the agent on my local machine?

Yes. You can run DevAssure locally using [@devassure/cli](https://www.npmjs.com/package/@devassure/cli).
