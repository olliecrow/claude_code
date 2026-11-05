#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=container/claude_common_lib.sh
source "$script_directory/claude_common_lib.sh"

if [[ "$#" -ne 0 ]]; then
    echo "Usage: $(basename "$0")" >&2
    exit 1
fi

failed=0

check() {
    local label="$1"
    shift
    local output=""

    if output="$("$@" 2>&1)"; then
        echo "[ok] $label"
    else
        echo "[fail] $label"
        if [[ -n "$output" ]]; then
            printf '%s\n' "$output" | tail -n 5 | sed 's/^/    /'
        fi
        failed=1
    fi
}

docker_is_rootful() {
    local security_options

    security_options="$(docker info --format '{{.SecurityOptions}}')" || return 1
    [[ "$security_options" != *name=rootless* ]]
}

echo "claude_code container doctor"
check "docker command" command -v docker
check "Docker daemon" docker info
check "rootful Docker (rootless Docker maps the container user to another uid)" docker_is_rootful
check "claude_code_container image" docker image inspect claude_code_container

if auth_source="$(container_auth_source)"; then
    echo "[ok] container-usable Claude authentication: $auth_source"
else
    echo "[fail] container-usable Claude authentication"
    echo "    Set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY, or log in on Linux."
    failed=1
fi

if [[ "$failed" -ne 0 ]]; then
    echo "doctor result: FAIL"
    exit 1
fi

echo "doctor result: PASS"
