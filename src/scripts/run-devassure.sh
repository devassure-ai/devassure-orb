#!/bin/bash
set -euo pipefail

normalize_boolean() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | xargs)"
  local default_value="${2:-false}"
  case "$value" in
    true|1)
      echo "true"
      ;;
    false|0)
      echo "false"
      ;;
    *)
      echo "$default_value"
      ;;
  esac
}

bool_to_string() {
  if is_true "$1"; then
    echo "true"
  else
    echo "false"
  fi
}

is_true() {
  [ "$(normalize_boolean "$1")" = "true" ]
}

add_arg() {
  local arg_name="$1"
  local arg_value="$2"
  if [ -n "$arg_value" ]; then
    cmd+=( "--${arg_name}=${arg_value}" )
  fi
}

add_flag() {
  local enabled="$1"
  local flag_name="$2"
  if is_true "$enabled"; then
    cmd+=( "--${flag_name}" )
  fi
}

resolve_default_branch() {
  local configured_default="$1"
  if [ -n "$configured_default" ]; then
    echo "$configured_default"
    return
  fi

  local branch
  branch="$(git remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF}' || true)"
  if [ -n "$branch" ]; then
    echo "$branch"
    return
  fi

  if git show-ref --verify --quiet refs/remotes/origin/main; then
    echo "main"
    return
  fi

  if git show-ref --verify --quiet refs/remotes/origin/master; then
    echo "master"
    return
  fi

  echo "main"
}

echo "Validating Node.js runtime..."
if ! command -v node >/dev/null 2>&1; then
  echo "Error: Node.js is required but was not found on PATH. Install Node.js 20 or above." >&2
  exit 1
fi

node_version="$(node --version)"
node_major="$(printf '%s' "$node_version" | sed -E 's/^v([0-9]+).*/\1/')"
if ! [[ "$node_major" =~ ^[0-9]+$ ]]; then
  echo "Error: Unable to parse Node.js version from '$node_version'. Node.js 20 or above is required." >&2
  exit 1
fi
if [ "$node_major" -lt 20 ]; then
  echo "Error: Node.js 20 or above is required. Found $node_version." >&2
  exit 1
fi

echo "Installing DevAssure CLI..."
npm i -g @devassure/cli@1

# Ensure CircleCI store_artifacts always has a valid source path.
mkdir -p .devassure-artifacts

echo "DevAssure CLI version:"
devassure version --no-ui

echo "Debug PARAM_HEADLESS: ${PARAM_HEADLESS:-}"
echo "Debug PARAM_ARCHIVE: ${PARAM_ARCHIVE:-}"
echo "Debug PARAM_VERBOSE: ${PARAM_VERBOSE:-}"
echo "Debug PARAM_DEBUG: ${PARAM_DEBUG:-}"

resolved_token="$PARAM_TOKEN"
if [[ "$resolved_token" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
  env_var_name="${BASH_REMATCH[1]}"
  resolved_token="${!env_var_name:-}"
elif [[ "$resolved_token" =~ ^\$([A-Za-z_][A-Za-z0-9_]*)$ ]]; then
  env_var_name="${BASH_REMATCH[1]}"
  resolved_token="${!env_var_name:-}"
fi

if [ -z "$resolved_token" ]; then
  resolved_token="${DEVASSURE_TOKEN:-}"
fi

if [ -z "$resolved_token" ]; then
  echo "Error: DevAssure token is required. Set the token parameter or DEVASSURE_TOKEN environment variable." >&2
  exit 1
fi

devassure add-token "$resolved_token" --no-ui

command_name="$PARAM_COMMAND"
case "$command_name" in
  setup|test|run|summary|archive|archive-report)
    ;;
  *)
    echo "Error: Unsupported command '$command_name'. Allowed: setup, test, run, summary, archive, archive-report." >&2
    exit 1
    ;;
esac

if [ "$command_name" = "test" ]; then
  if [ ! -d .git ]; then
    echo "Error: DevAssure test command requires a checked-out git repository." >&2
    exit 1
  fi

  current_branch="$(git branch --show-current || true)"
  if [ -z "$current_branch" ]; then
    echo "Error: Detached HEAD detected. Check out a branch ref before running test mode." >&2
    exit 1
  fi

  default_branch="$(resolve_default_branch "$PARAM_DEFAULT_BRANCH")"
  target_branch="$default_branch"
  if [ -n "$PARAM_TARGET" ]; then
    target_branch="$PARAM_TARGET"
  fi

  echo "Preparing git refs (target/default: $target_branch)..."
  git fetch origin "+refs/heads/${target_branch}:refs/remotes/origin/${target_branch}"
  git remote set-head origin "${target_branch}" || true

  if [ -n "$PARAM_SOURCE" ]; then
    echo "Preparing source branch ref: $PARAM_SOURCE"
    git fetch origin "+refs/heads/${PARAM_SOURCE}:refs/remotes/origin/${PARAM_SOURCE}"
    git checkout -B "$PARAM_SOURCE" "origin/$PARAM_SOURCE"
  fi
fi

if [ "$command_name" = "archive" ]; then
  command_name="archive-report"
fi
cmd=(devassure "$command_name" --no-ui)

if [ -n "$PARAM_WORKERS" ] && [ "$PARAM_WORKERS" != "0" ]; then
  if ! [[ "$PARAM_WORKERS" =~ ^[0-9]+$ ]] || [ "$PARAM_WORKERS" -le 0 ]; then
    echo "Error: workers must be an integer greater than 0. Received '$PARAM_WORKERS'." >&2
    exit 1
  fi
fi

normalized_headless="$(normalize_boolean "$PARAM_HEADLESS" "true")"
normalized_archive="$(normalize_boolean "$PARAM_ARCHIVE" "true")"
normalized_verbose="$(normalize_boolean "$PARAM_VERBOSE" "false")"
normalized_debug="$(normalize_boolean "$PARAM_DEBUG" "false")"

case "$command_name" in
  setup)
    add_flag "$normalized_verbose" "verbose"
    add_flag "$normalized_debug" "debug"
    ;;
  test)
    add_arg "path" "$PARAM_PATH"
    add_arg "source" "$PARAM_SOURCE"
    add_arg "target" "$PARAM_TARGET"
    add_arg "commit_id" "$PARAM_COMMIT_ID"
    add_arg "url" "$PARAM_URL"
    add_arg "workers" "$PARAM_WORKERS"
    add_arg "environment" "$PARAM_ENVIRONMENT"
    cmd+=( "--headless=$(bool_to_string "$normalized_headless")" )
    add_flag "$normalized_verbose" "verbose"
    add_flag "$normalized_debug" "debug"
    ;;
  run)
    add_arg "path" "$PARAM_PATH"
    add_arg "filter" "$PARAM_FILTER"
    add_arg "query" "$PARAM_QUERY"
    add_arg "tag" "$PARAM_TAG"
    add_arg "priority" "$PARAM_PRIORITY"
    add_arg "folder" "$PARAM_FOLDER"
    add_arg "url" "$PARAM_URL"
    add_arg "workers" "$PARAM_WORKERS"
    add_arg "environment" "$PARAM_ENVIRONMENT"
    cmd+=( "--headless=$(bool_to_string "$normalized_headless")" )
    add_flag "$normalized_verbose" "verbose"
    add_flag "$normalized_debug" "debug"
    ;;
  summary)
    if [ -n "$PARAM_SESSION_ID" ]; then
      cmd+=( "--session_id=${PARAM_SESSION_ID}" )
    else
      cmd+=( "--last" )
    fi
    add_flag "$normalized_verbose" "verbose"
    add_flag "$normalized_debug" "debug"
    ;;
  archive-report)
    if [ -n "$PARAM_SESSION_ID" ]; then
      cmd+=( "--session_id=${PARAM_SESSION_ID}" )
    else
      cmd+=( "--last" )
    fi
    add_flag "$normalized_verbose" "verbose"
    add_flag "$normalized_debug" "debug"
    ;;
esac

printf 'Running:'
printf ' %q' "${cmd[@]}"
printf '\n'
"${cmd[@]}"

archive_path=""
if [ "$PARAM_COMMAND" = "test" ] || [ "$PARAM_COMMAND" = "run" ]; then
  echo "Printing summary for last session..."
  devassure summary --last --no-ui

  echo "Exporting JUnit XML report to .devassure-artifacts/"
  export_cmd=(devassure export-report --output-dir ".devassure-artifacts/" --last --format junit-xml --no-ui)
  if is_true "$normalized_verbose"; then
    export_cmd+=( "--verbose" )
  fi
  if is_true "$normalized_debug"; then
    export_cmd+=( "--debug" )
  fi
  printf 'Running:'
  printf ' %q' "${export_cmd[@]}"
  printf '\n'
  "${export_cmd[@]}"

  if is_true "$normalized_archive"; then
    archive_log_file="$(mktemp)"
    archive_cmd=(devassure archive-report --last "--output-dir=.devassure-artifacts/" --no-ui)
    if is_true "$normalized_verbose"; then
      archive_cmd+=( "--verbose" )
    fi
    if is_true "$normalized_debug"; then
      archive_cmd+=( "--debug" )
    fi
    printf 'Running:'
    printf ' %q' "${archive_cmd[@]}"
    printf '\n'
    "${archive_cmd[@]}"
  fi

  echo "Listing .devassure-artifacts/"
  ls -la .devassure-artifacts/

  minimum_score="$(printf '%s' "$PARAM_MINIMUM_SCORE" | xargs)"
  if [[ "$minimum_score" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk -v value="$minimum_score" 'BEGIN { exit !(value > 0) }'; then
    summary_log_file="$(mktemp)"
    devassure summary --last --no-ui | tee "$summary_log_file"
    score_value="$(awk -F 'score:' '/score:/ { print $2; exit }' "$summary_log_file" | xargs)"

    if [ -z "$score_value" ] || [ "$score_value" = "N/A" ]; then
      echo "Error: score is missing or N/A in devassure summary output." >&2
      exit 1
    fi
    if ! [[ "$score_value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      echo "Error: score '$score_value' is not a valid number." >&2
      exit 1
    fi
    if awk -v score="$score_value" -v minimum="$minimum_score" 'BEGIN { exit !(score < minimum) }'; then
      echo "Test score '$score_value' is less than the minimum expected score ($minimum_score)." >&2
      exit 1
    fi
  else
    echo "Skipping score check: minimum_score '$minimum_score' is not a valid positive number."
  fi
fi
