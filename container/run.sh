#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=container/claude_common_lib.sh
source "$script_directory/claude_common_lib.sh"

usage() {
    echo "Usage: $(basename "$0") /path/to/project [--shell]"
}

if [[ "$#" -lt 1 || "$#" -gt 2 ]]; then
    usage >&2
    exit 1
fi

project_directory="$1"
run_mode="${2:-}"

if [[ -n "$run_mode" && "$run_mode" != "--shell" ]]; then
    echo "Error: unsupported mode: $run_mode" >&2
    usage >&2
    exit 1
fi

if [[ ! -t 0 || ! -t 1 ]]; then
    echo "Error: run.sh needs a terminal. Use run_command.sh for a script." >&2
    exit 1
fi

require_directory "$project_directory"
require_claude_auth
require_docker

project_directory="$(absolute_directory "$project_directory")"
host_timezone="$(detect_host_timezone)"
project_name="$(safe_container_component "$(basename "$project_directory")")"
container_name="claude_code_${project_name}_$$"

run_directory=""
home_directory=""
container_id_file=""

cleanup() {
    local exit_code=$?

    if [[ -n "$run_directory" ]]; then
        if ! release_recorded_container "$run_directory"; then
            echo "Error: run directory cleanup failed. Kept $run_directory" >&2
            if [[ "$exit_code" -eq 0 ]]; then
                exit_code=1
            fi
        fi
    fi
    exit "$exit_code"
}

run_directory="$(private_run_directory "$project_directory")" || exit 1
home_directory="$run_directory/home"
container_id_file="$run_directory/container.id"
trap cleanup EXIT
mkdir -m 700 "$home_directory"
populate_container_home "$home_directory"

print_trust_warning
echo "Project: $project_directory"
echo "Starting container: $container_name"
start_claude_container "$container_name" "$project_directory" "$host_timezone" "$home_directory" "$container_id_file" >/dev/null

if [[ "$run_mode" == "--shell" ]]; then
    docker exec -it -w /workspace "$(< "$container_id_file")" bash
else
    docker exec -it -w /workspace "$(< "$container_id_file")" \
        claude --model claude-opus-5-5 --dangerously-skip-permissions
fi
