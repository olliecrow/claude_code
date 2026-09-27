#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=container/claude_common_lib.sh
source "$script_directory/claude_common_lib.sh"

usage() {
    echo "Usage: $(basename "$0") /path/to/project \"prompt\""
}

if [[ "$#" -ne 2 ]]; then
    usage >&2
    exit 1
fi

project_directory="$1"
prompt="$2"
timeout_seconds="${CLAUDE_TIMEOUT_SECONDS:-5400}"

if [[ -z "${prompt//[[:space:]]/}" ]]; then
    echo "Error: prompt must not be empty." >&2
    exit 1
fi

if [[ ! "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: CLAUDE_TIMEOUT_SECONDS must be a positive integer." >&2
    exit 1
fi

require_directory "$project_directory"
require_claude_auth
require_docker

project_directory="$(absolute_directory "$project_directory")"
host_timezone="$(detect_host_timezone)"
project_name="$(safe_container_component "$(basename "$project_directory")")"
container_name="claude_code_command_${project_name}_$$"

cleanup() {
    stop_container "$container_name"
}
trap cleanup EXIT

print_trust_warning
echo "Project: $project_directory"
echo "Starting container: $container_name"
start_claude_container "$container_name" "$project_directory" "$host_timezone" >/dev/null

printf '%s\n' "$prompt" | docker exec -i -w /workspace "$container_name" \
    claude -p --model claude-opus-5-5 --dangerously-skip-permissions &
command_pid=$!

elapsed_seconds=0
poll_seconds=5
while kill -0 "$command_pid" 2>/dev/null; do
    if (( elapsed_seconds >= timeout_seconds )); then
        echo "Error: Claude timed out after ${timeout_seconds} seconds." >&2
        kill "$command_pid" 2>/dev/null || true
        wait "$command_pid" 2>/dev/null || true
        exit 124
    fi
    sleep "$poll_seconds"
    elapsed_seconds=$((elapsed_seconds + poll_seconds))
done

if wait "$command_pid"; then
    echo "Claude completed the prompt."
else
    exit_code=$?
    echo "Error: Claude exited with status $exit_code." >&2
    exit "$exit_code"
fi
