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

if [[ -z "${prompt//[[:space:]]/}" ]]; then
    echo "Error: prompt must not be empty." >&2
    exit 1
fi

timeout_seconds="$(claude_timeout_seconds)"

require_directory "$project_directory"
require_claude_auth
require_docker

project_directory="$(absolute_directory "$project_directory")"
host_timezone="$(detect_host_timezone)"
project_name="$(safe_container_component "$(basename "$project_directory")")"
container_name="claude_code_command_${project_name}_$$"

run_directory=""
home_directory=""
container_id_file=""

cleanup() {
    if [[ -n "$container_id_file" ]]; then
        remove_recorded_container "$container_id_file"
    fi
    if [[ -n "$run_directory" ]]; then
        rm -rf -- "$run_directory"
    fi
}

run_directory="$(mktemp -d)"
home_directory="$run_directory/home"
container_id_file="$run_directory/container.id"
trap cleanup EXIT
mkdir "$home_directory"
populate_container_home "$home_directory"

print_trust_warning
echo "Project: $project_directory"
echo "Starting container: $container_name"
start_claude_container "$container_name" "$project_directory" "$host_timezone" "$home_directory" "$container_id_file" >/dev/null

printf '%s\n' "$prompt" | docker exec -i -w /workspace "$container_name" \
    claude -p --model claude-opus-5-5 --dangerously-skip-permissions &

if wait_for_pid "$!" "$timeout_seconds"; then
    echo "Claude completed the prompt."
else
    exit_code=$?
    echo "Error: Claude exited with status $exit_code." >&2
    exit "$exit_code"
fi
