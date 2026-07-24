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

    if "$@" >/dev/null 2>&1; then
        echo "[ok] $label"
    else
        echo "[fail] $label"
        failed=1
    fi
}

echo "claude_code container doctor"
check "docker command" command -v docker
check "Docker daemon" docker info
check "claude_code_container image" docker image inspect claude_code_container
check "host Claude configuration" test -d "$HOME/.claude"
check "container-usable Claude authentication" has_container_auth

if [[ "$failed" -ne 0 ]]; then
    echo "doctor result: FAIL"
    exit 1
fi

echo "doctor result: PASS"
