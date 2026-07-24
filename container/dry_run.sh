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
    action="launch Claude with the sonnet alias"
fi

print_trust_warning
cat <<EOF

Dry run
Project: $project_directory
Container: $container_name
Action: $action
Timezone: ${host_timezone:-not detected}

Planned sequence:
1. Start claude_code_container with bridge networking.
2. Mount the project at /workspace and ~/.claude at /home/dev/.claude.
3. Pass the configured container authentication environment variable, if used.
4. $action.
5. Remove the container when the session ends.

No Docker command was run and no project file was changed.
EOF
