# DevAssure Orb

CircleCI orb to run [@devassure/cli](https://www.npmjs.com/package/@devassure/cli) commands in CI.

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
  - optionally runs `archive-report` and stores artifacts.

## Create a DevAssure token

1. Log in to [https://app.devassure.io](https://app.devassure.io).
2. Generate an API token from account settings.
3. Add it in CircleCI project settings or context as `DEVASSURE_TOKEN`.

## Prerequisites

- Linux/macOS CircleCI executors with Node 20+.
- `checkout` enabled for branch-aware `test` flows.
- Full branch refs available when using `source`/`target` comparisons.

## Usage

### Minimal (defaults to `test`)

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
          workers: "2"
          minimum_score: "80"
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
          workers: "2"
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
| `checkout` | `true` | Run `checkout` before execution |
| `executor_tag` | `24.4` | `cimg/node` tag for default executor |
| `command` | `test` | `setup`, `test`, `run`, `summary`, `archive`, `archive-report` |
| `token` | _empty_ | DevAssure token. Fallback: `DEVASSURE_TOKEN` |
| `path` | _empty_ | Used by `test`, `run` |
| `source` | _empty_ | Used by `test` |
| `target` | _empty_ | Used by `test` |
| `default_branch` | _empty_ | Used by `test` when `target` is unset |
| `commit_id` | _empty_ | Used by `test` |
| `filter` | _empty_ | Used by `run` |
| `query` | _empty_ | Used by `run` |
| `tag` | _empty_ | Used by `run` |
| `priority` | _empty_ | Used by `run` |
| `folder` | _empty_ | Used by `run` |
| `url` | _empty_ | Used by `test`, `run` |
| `headless` | `true` | Used by `test`, `run`; always passed |
| `session_id` | _empty_ | Used by `summary`, `archive`, `archive-report` |
| `archive` | `true` | For `test`/`run`, run `archive-report --last` |
| `minimum_score` | `75` | For `test`/`run`, score gate using `summary --last` |
| `workers` | _empty_ | For `test`/`run`, must be integer > 0 when set |
| `environment` | _empty_ | Environment for `test`, `run` |
| `verbose` | `false` | Enable `--verbose` |
| `debug` | `false` | Enable `--debug` |

## Branch Safety Behavior (`command: test`)

- Verifies `.git` exists and current HEAD is attached to a branch.
- Resolves default branch using:
  1. `default_branch` parameter
  2. `origin/HEAD` from remote metadata
  3. fallback to `main` (or `master` if available remotely).
- Fetches target/default branch ref from `origin`.
- If `source` is provided, fetches source ref and checks it out.

## Artifacts and score validation

- Artifacts are stored under `.devassure-artifacts`.
- If archive runs successfully, `.devassure-artifacts/archive_path.txt` contains the generated path.
- Score gate runs for `test`/`run` when `minimum_score` is a valid positive number.
- The job fails when score is missing, `N/A`, non-numeric, or below the threshold.

## Runner sizing recommendation

- Baseline for parallel browser execution: `4 vCPU / 16 GB RAM`.
- Increase machine size when increasing `workers`.
