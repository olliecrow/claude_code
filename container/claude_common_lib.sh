#!/usr/bin/env bash

# Shared helpers for the container launch scripts. This file does not set shell
# options or traps; each caller owns its process lifecycle.

container_home=/home/dev

detect_host_timezone() {
    local timezone=""

    if [[ -L /etc/localtime ]]; then
        timezone="$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')"
    elif [[ -f /etc/timezone ]]; then
        timezone="$(sed -n '1p' /etc/timezone)"
    fi

    # Keep only IANA-style names. Abbreviations such as EST are not valid TZ
    # names, and a wrong zone is worse than the container default of UTC.
    if [[ "$timezone" == "UTC" || "$timezone" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)+$ ]]; then
        printf '%s\n' "$timezone"
    fi
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

# Docker parses --mount values as CSV, so these characters would split or
# corrupt the option.
require_mount_safe_path() {
    local path_value="$1"

    if [[ "$path_value" == *,* || "$path_value" == *\"* || "$path_value" == *$'\n'* ]]; then
        echo "Error: path contains a character Docker mount options cannot carry: $path_value" >&2
        return 1
    fi
}

mounts_host_config() {
    [[ "${CLAUDE_CONTAINER_MOUNT_HOST_CONFIG:-0}" == "1" ]]
}

# Prints the authentication source the container will use, without its value.
# An OAuth token wins over an API key. Only that one value is forwarded.
container_auth_source() {
    if [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]]; then
        echo "CLAUDE_CODE_OAUTH_TOKEN"
    elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        echo "ANTHROPIC_API_KEY"
    elif [[ -f "$HOME/.claude/.credentials.json" && -s "$HOME/.claude/.credentials.json" ]]; then
        echo "credentials file"
    else
        return 1
    fi
}

# Prints the one auth variable to forward, or nothing when the credentials
# file is the source. Returns 1 when no usable auth exists.
container_auth_variable() {
    local auth_source=""

    auth_source="$(container_auth_source)" || return 1
    case "$auth_source" in
        CLAUDE_CODE_OAUTH_TOKEN|ANTHROPIC_API_KEY)
            printf '%s\n' "$auth_source"
            ;;
    esac
}

require_claude_auth() {
    if mounts_host_config && [[ ! -d "$HOME/.claude" ]]; then
        echo "Error: CLAUDE_CONTAINER_MOUNT_HOST_CONFIG=1 but ~/.claude does not exist." >&2
        return 1
    fi

    if ! container_auth_source >/dev/null; then
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

# Fills a new, empty host directory that becomes the container home. Only the
# credentials file is copied, and only when no auth variable is set.
populate_container_home() {
    local home_directory="$1"

    chmod 700 "$home_directory"
    mkdir -m 700 "$home_directory/.claude"

    if mounts_host_config; then
        return 0
    fi

    # .claude.json records that first-launch setup is done, so an interactive
    # run does not repeat it every time.
    printf '{"hasCompletedOnboarding": true}\n' > "$home_directory/.claude/.claude.json"

    if [[ "$(container_auth_source)" == "credentials file" ]]; then
        cp "$HOME/.claude/.credentials.json" "$home_directory/.claude/.credentials.json"
        chmod 600 "$home_directory/.claude/.credentials.json"
    fi
}

start_claude_container() {
    local container_name="$1"
    local project_directory="$2"
    local host_timezone="$3"
    local home_directory="$4"
    local container_id_file="${5:-}"
    local auth_variable=""
    local docker_arguments=(
        run
        -d
        --name "$container_name"
        --mount "type=bind,source=$project_directory,target=/workspace"
        --mount "type=bind,source=$home_directory,target=$container_home"
        --network bridge
        --user "$(id -u):$(id -g)"
        --cap-drop ALL
        --security-opt no-new-privileges:true
        --pids-limit 4096
        --workdir /workspace
        --env TERM=xterm-256color
        --env "HOME=$container_home"
        --env "CLAUDE_CONFIG_DIR=$container_home/.claude"
    )

    require_mount_safe_path "$project_directory" || return 1
    require_mount_safe_path "$home_directory" || return 1
    # Mask Git metadata after the writable project mount. A worktree has a
    # .git file; its external metadata is not added to the container mounts.
    if [[ -e "$project_directory/.git" ]]; then
        require_mount_safe_path "$project_directory/.git" || return 1
        docker_arguments+=(--mount "type=bind,source=$project_directory/.git,target=/workspace/.git,readonly")
    fi
    if mounts_host_config; then
        require_mount_safe_path "$HOME/.claude" || return 1
        docker_arguments+=(--mount "type=bind,source=$HOME/.claude,target=$container_home/.claude")
    fi

    if [[ -n "$host_timezone" ]]; then
        docker_arguments+=(--env "TZ=$host_timezone")
    fi
    if auth_variable="$(container_auth_variable)"; then
        if [[ -n "$auth_variable" ]]; then
            docker_arguments+=(--env "$auth_variable")
        fi
    fi
    # Record the container this call creates, even when startup fails.
    # Cleanup removes that id and never a container chosen by name.
    if [[ -n "$container_id_file" ]]; then
        if [[ -e "$container_id_file" ]]; then
            echo "Error: container id file already exists." >&2
            return 1
        fi
        docker_arguments+=(--cidfile "$container_id_file")
    fi

    docker_arguments+=(claude_code_container tail -f /dev/null)
    docker "${docker_arguments[@]}"
}

# Prints CLAUDE_TIMEOUT_SECONDS, default 5400, after checking it.
claude_timeout_seconds() {
    local timeout_seconds="${CLAUDE_TIMEOUT_SECONDS:-5400}"

    if [[ ! "$timeout_seconds" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: CLAUDE_TIMEOUT_SECONDS must be a positive integer." >&2
        return 1
    fi
    printf '%s\n' "$timeout_seconds"
}

# Waits for a background process and returns its status, or 124 after the
# timeout. The caller's EXIT trap removes the container.
wait_for_pid() {
    local process_id="$1"
    local timeout_seconds="$2"
    local elapsed_seconds=0

    while kill -0 "$process_id" 2>/dev/null; do
        if (( elapsed_seconds >= timeout_seconds )); then
            echo "Error: Claude timed out after ${timeout_seconds} seconds." >&2
            kill "$process_id" 2>/dev/null || true
            wait "$process_id" 2>/dev/null || true
            return 124
        fi
        sleep 1
        elapsed_seconds=$((elapsed_seconds + 1))
    done
    wait "$process_id"
}

# Removes the container recorded by docker run --cidfile. A missing or empty
# file means this run did not create a container, so nothing is removed.
remove_recorded_container() {
    local container_id_file="$1"
    local container_id=""

    if [[ ! -s "$container_id_file" ]]; then
        return 0
    fi
    container_id="$(tr -d '[:space:]' < "$container_id_file")"
    if [[ ! "$container_id" =~ ^[0-9a-fA-F]{64}$ ]]; then
        echo "Error: container id file did not contain a container id." >&2
        return 0
    fi
    docker rm -f "$container_id" >/dev/null 2>&1 || true
}

print_trust_warning() {
    cat <<'EOF'
Warning: this container has network access and a read-write project mount.
Claude permission checks are bypassed. Use trusted inputs only.
Any auth variable forwarded into the container is visible to local Docker inspection while it runs.
EOF
    if mounts_host_config; then
        echo "Host Claude config (~/.claude) is mounted read-write."
    else
        echo "Claude config is a temporary directory that is deleted after the run."
    fi
}
