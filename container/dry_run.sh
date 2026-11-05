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

project_directory="$(absolute_directory "$project_directory")"
host_timezone="$(detect_host_timezone)"
project_name="$(safe_container_component "$(basename "$project_directory")")"
container_name="claude_code_${project_name}_<pid>"

if [[ "$run_mode" == "--shell" ]]; then
    action="open an interactive shell"
else
    action="launch Claude Opus 5.5"
fi

if mounts_host_config; then
    config_mount="Mount ~/.claude read-write at /home/dev/.claude."
else
    config_mount="Mount a new temporary home at /home/dev, with only the credentials file if that is the auth source."
fi
auth_source="$(container_auth_source)"
if [[ "$auth_source" == "credentials file" ]]; then
    auth_forward="Forwards no auth environment variable."
else
    auth_forward="Forwards only ${auth_source}."
fi

print_trust_warning
cat <<EOF

Dry run
Project: $project_directory
Container: $container_name
Action: $action
Timezone: ${host_timezone:-not detected}
Authentication: $auth_source
$auth_forward

Planned sequence:
1. Start claude_code_container with bridge networking, as uid $(id -u), with all capabilities dropped.
2. Mount the project at /workspace; mount its .git read-only if present (directory or worktree file).
3. $config_mount
4. $action.
5. Remove the container and the temporary home when the session ends.

No Docker command was run and no project file was changed.
EOF
