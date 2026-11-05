#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_directory"

usage() {
    echo "Usage: $(basename "$0") [--minimal] [--no-cache]"
}

full_image=1
cache_arguments=()

for argument in "$@"; do
    case "$argument" in
        --minimal)
            full_image=0
            ;;
        --no-cache)
            cache_arguments=(--no-cache)
            ;;
        *)
            echo "Error: unsupported option: $argument" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ "$full_image" -eq 1 ]]; then
    echo "Building the full claude_code_container image."
else
    echo "Building the minimal claude_code_container image."
fi

docker build \
    --pull \
    ${cache_arguments[@]+"${cache_arguments[@]}"} \
    --build-arg "FULL_IMAGE=$full_image" \
    --tag claude_code_container \
    .

echo "Built image: claude_code_container"
