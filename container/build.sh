#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_directory"

include_build_tools=1
include_extra_tools=1

if [[ "$#" -gt 1 ]]; then
    echo "Usage: $(basename "$0") [--minimal]" >&2
    exit 1
fi

if [[ "${1:-}" == "--minimal" ]]; then
    include_build_tools=0
    include_extra_tools=0
elif [[ "$#" -eq 1 ]]; then
    echo "Error: unsupported option: $1" >&2
    echo "Usage: $(basename "$0") [--minimal]" >&2
    exit 1
fi

if [[ "$include_build_tools" -eq 1 ]]; then
    echo "Building the full claude_code_container image."
else
    echo "Building the minimal claude_code_container image."
fi

docker build \
    --pull \
    --no-cache \
    --build-arg "INCLUDE_BUILD_TOOLS=$include_build_tools" \
    --build-arg "INCLUDE_EXTRA_TOOLS=$include_extra_tools" \
    --tag claude_code_container \
    .

echo "Built image: claude_code_container"
