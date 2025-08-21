#!/bin/bash

# Claude Code Terminal Container - System-Wide Authentication (IMPROVED)
# Uses your Mac's global Claude authentication for all projects
# IMPROVEMENT: Adds additional directories to prevent permission prompts

set -e

if [ $# -eq 0 ]; then
    echo "Error: Please specify a directory to mount"
    echo "Usage: $0 /path/to/your/project [--shell]"
    exit 1
fi

REPO_DIR="$1"
SHELL_MODE="$2"

# Verify directory exists
if [ ! -d "$REPO_DIR" ]; then
    echo "Error: Directory '$REPO_DIR' does not exist"
    exit 1
fi

# Get absolute path
REPO_DIR="$(cd "$REPO_DIR" && pwd)"

# Check if Claude authentication exists on Mac
if [ ! -d "$HOME/.claude" ]; then
    echo "Error: No Claude authentication found on your Mac"
    echo "Please run 'claude' on your Mac first and complete authentication"
    echo "This works with both API and subscription authentication"
    exit 1
fi

echo "Using system-wide Claude authentication from Mac"
echo "Project directory: $REPO_DIR"
echo "Authentication: ~/.claude -> /home/dev/.claude (system-wide)"
echo "Container will have access to repo directory only"

# Detect host timezone (macOS)
HOST_TZ=""
if [ -f "/etc/localtime" ]; then
    # Try to read the timezone from the localtime symlink
    HOST_TZ=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
fi

# If that didn't work, try alternative methods
if [ -z "$HOST_TZ" ]; then
    # Try systemsetup (macOS specific)
    HOST_TZ=$(systemsetup -gettimezone 2>/dev/null | awk -F': ' '{print $2}')
fi

# If still no timezone, try date command
if [ -z "$HOST_TZ" ]; then
    HOST_TZ=$(date +%Z 2>/dev/null)
fi

if [ -n "$HOST_TZ" ]; then
    echo "Host timezone detected: $HOST_TZ"
else
    echo "Warning: Could not detect host timezone, container will use UTC"
fi

echo ""

# Source shared settings library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
    --network bridge \
    --user 1000:1000 \
    --workdir /workspace \
    --env TERM=xterm-256color \
    --env IS_SANDBOX=1 \
    --env CLAUDE_CONFIG_DIR=/home/dev/.claude \
    --env CLAUDE_CODE_BYPASS_ALL_PERMISSIONS=1 \
    --env CLAUDE_CODE_SUPPRESS_UI_PROMPTS=1 \
    --env ANTHROPIC_DISABLE_SAFETY_CHECKS=1 \
    --env CLAUDE_CODE_ENTERPRISE_MODE=1 \
    --env DISABLE_AUTOUPDATER=1 \
    --env CLAUDE_CODE_ENABLE_TELEMETRY=0 \
    --env CLAUDE_WORKING_DIRECTORIES="/workspace:/workspace/..:/:/home:/etc:/usr:/var:/tmp:/root" \
    ${HOST_TZ:+--env TZ="$HOST_TZ"} \
    claude_code_container tail -f /dev/null

# Now exec into the container interactively
echo "Entering container..."
if [ "$SHELL_MODE" = "--shell" ]; then
    docker exec -it "$CONTAINER_NAME" bash --login
else
    docker exec -it "$CONTAINER_NAME" bash -c "cd /workspace && claude --dangerously-skip-permissions"
fi

# Clean up container when done
echo "Cleaning up container..."
docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1

echo "Container exited."