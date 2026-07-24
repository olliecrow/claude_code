#!/usr/bin/env bash

# Shared helpers for the container launch scripts. This file does not set shell
# options or traps; each caller owns its process lifecycle.

detect_host_timezone() {
    local timezone=""

    if [[ -L /etc/localtime ]]; then
        timezone="$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')"
    elif [[ -f /etc/timezone ]]; then
        timezone="$(sed -n '1p' /etc/timezone)"
    fi

    if [[ -z "$timezone" ]]; then
        timezone="$(date +%Z 2>/dev/null || true)"
    fi

    printf '%s\n' "$timezone"
}

require_directory() {
    local directory_path="$1"

    if [[ ! -d "$directory_path" ]]; then
        echo "Error: directory does not exist: $directory_path" >&2
        return 1
    fi
}

absolute_directory() {
    local directory_path="$1"
    (
        cd -- "$directory_path" || exit
        pwd -P
    )
}

has_container_auth() {
    [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] \
        || [[ -n "${ANTHROPIC_API_KEY:-}" ]] \
        || [[ -f "$HOME/.claude/.credentials.json" ]]
}

require_claude_auth() {
    if [[ ! -d "$HOME/.claude" ]]; then
        echo "Error: Claude configuration was not found at ~/.claude." >&2
        echo "Run Claude Code on the host once to create it." >&2
        return 1
    fi

    if ! has_container_auth; then
        echo "Error: no authentication usable inside Docker was found." >&2
        echo "Set CLAUDE_CODE_OAUTH_TOKEN or ANTHROPIC_API_KEY." >&2
        echo "A macOS Keychain login is not available inside the container." >&2
        return 1
    fi
}

require_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "Error: docker was not found in PATH." >&2
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "Error: the Docker daemon is not reachable." >&2
        return 1
    fi

    if ! docker image inspect claude_code_container >/dev/null 2>&1; then
        echo "Error: image claude_code_container is missing. Run ./container/build.sh." >&2
        return 1
    fi
}

safe_container_component() {
    local raw_name="$1"
    printf '%s' "$raw_name" | LC_ALL=C tr -c 'A-Za-z0-9_.-' '_'
}

start_claude_container() {
    local container_name="$1"
    local project_directory="$2"
    local host_timezone="$3"
    local docker_arguments=(
        run
        -d
        --name "$container_name"
        --mount "type=bind,source=$project_directory,target=/workspace"
        --mount "type=bind,source=$HOME/.claude,target=/home/dev/.claude"
        --network bridge
        --user 1000:1000
        --workdir /workspace
        --env TERM=xterm-256color
        --env CLAUDE_CONFIG_DIR=/home/dev/.claude
        --env DISABLE_AUTOUPDATER=1
    )

    if [[ -n "$host_timezone" ]]; then
        docker_arguments+=(--env "TZ=$host_timezone")
    fi
    if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
        docker_arguments+=(--env CLAUDE_CODE_OAUTH_TOKEN)
    fi
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        docker_arguments+=(--env ANTHROPIC_API_KEY)
    fi

    docker_arguments+=(claude_code_container tail -f /dev/null)
    docker "${docker_arguments[@]}"
}

stop_container() {
    local container_name="$1"

    if [[ -n "$container_name" ]]; then
        docker rm -f "$container_name" >/dev/null 2>&1 || true
    fi
}

print_trust_warning() {
    cat <<'EOF'
Warning: this container has network access and read-write mounts for the project
and ~/.claude. Claude permission checks are bypassed. Use trusted inputs only.
Auth environment variables are visible to local Docker inspection while it runs.
EOF
}
