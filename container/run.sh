#!/bin/bash

# Claude Code Terminal Container - System-Wide Authentication (IMPROVED)
# Uses your Mac's global Claude authentication for all projects
# IMPROVEMENT: Adds additional directories to prevent permission prompts

set -e

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/claude_common_lib.sh"

if [ $# -eq 0 ]; then
    echo "Error: Please specify a directory to mount"
    echo "Usage: $0 /path/to/your/project [--shell]"
    exit 1
fi

REPO_DIR="$1"
SHELL_MODE="$2"

# Verify directory exists
if ! validate_directory "$REPO_DIR"; then
    exit 1
fi

# Get absolute path
REPO_DIR="$(get_absolute_path "$REPO_DIR")"

# Check if Claude authentication exists on Mac
if ! check_claude_auth; then
    exit 1
fi

echo "Using system-wide Claude authentication from Mac"
echo "Project directory: $REPO_DIR"
echo "Authentication: ~/.claude -> /home/dev/.claude (system-wide)"
echo "Container will have access to repo directory only"

# Detect host timezone (macOS)
HOST_TZ="$(detect_host_timezone)"

if [ -n "$HOST_TZ" ]; then
    echo "Host timezone detected: $HOST_TZ"
else
    echo "Warning: Could not detect host timezone, container will use UTC"
fi

echo ""

# Source shared settings library
source "$SCRIPT_DIR/claude_settings_lib.sh"

# Setup container settings
setup_container_settings "$REPO_DIR"

# Ensure restoration on any exit, including crashes
trap restore_settings_json EXIT

# Start container in detached mode first
CONTAINER_NAME="claude_code_$(basename "$REPO_DIR")_$$"
echo "Starting container: $CONTAINER_NAME"

docker run -d \
    --name "$CONTAINER_NAME" \
    --mount type=bind,source="$REPO_DIR",target=/workspace \
    --mount type=bind,source="$HOME/.claude",target=/home/dev/.claude \
    $(get_base_docker_env_args) \
    ${HOST_TZ:+--env TZ="$HOST_TZ"} \
    claude_code_container tail -f /dev/null

# Now exec into the container interactively
echo "Entering container..."
if [ "$SHELL_MODE" = "--shell" ]; then
    docker exec -it "$CONTAINER_NAME" bash --login
else
    docker exec -it "$CONTAINER_NAME" bash -c "cd /workspace && claude --model=opus --dangerously-skip-permissions"
fi

# Clean up container when done
echo "Cleaning up container..."
docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1

echo "Container exited."