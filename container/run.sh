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

require_directory "$project_directory"
require_claude_auth
require_docker

project_directory="$(absolute_directory "$project_directory")"
host_timezone="$(detect_host_timezone)"
project_name="$(safe_container_component "$(basename "$project_directory")")"
container_name="claude_code_${project_name}_$$"

cleanup() {
    stop_container "$container_name"
}
trap cleanup EXIT

print_trust_warning
echo "Project: $project_directory"
echo "Starting container: $container_name"
start_claude_container "$container_name" "$project_directory" "$host_timezone" >/dev/null

if [[ "$run_mode" == "--shell" ]]; then
    docker exec -it -w /workspace "$container_name" bash
else
    docker exec -it -w /workspace "$container_name" \
        claude --model sonnet --dangerously-skip-permissions
fi
