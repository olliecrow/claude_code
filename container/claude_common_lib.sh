#!/bin/bash
# claude_common_lib.sh - Common utilities for Claude Code scripts
# 
# IMPORTANT: This library:
# - Does NOT set any trap handlers (scripts manage their own)
# - Does NOT call exit (returns error codes instead)
# - Does NOT output to stderr (maintains stdout for compatibility)
# - Does NOT source other libraries (avoid circular dependencies)

# Detect host timezone (identical across all scripts)
detect_host_timezone() {
    local HOST_TZ=""
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
    
    echo "$HOST_TZ"
}

# Check Claude authentication
check_claude_auth() {
    if [ ! -d "$HOME/.claude" ]; then
        echo "Error: No Claude authentication found on your system"
        echo "Please run 'claude' first and complete authentication"
        echo "This works with both API and subscription authentication"
        return 1
    fi
    return 0
}

# Validate directory exists
validate_directory() {
    local dir="$1"
    if [ ! -d "$dir" ]; then
        echo "Error: Directory '$dir' does not exist"
        return 1
    fi
    return 0
}

# Get absolute path of directory (assumes already validated)
get_absolute_path() {
    local dir="$1"
    cd "$dir" && pwd
}

# Get base Docker environment args as a string
# Usage: Add $(get_base_docker_env_args) to docker run command
get_base_docker_env_args() {
    echo "--network bridge \
--user 1000:1000 \
--workdir /workspace \
--env TERM=xterm-256color \
--env IS_SANDBOX=1 \
--env CLAUDE_HOME=/home/dev/.claude \
--env CLAUDE_CONFIG_DIR=/home/dev/.claude \
--env CLAUDE_CODE_BYPASS_ALL_PERMISSIONS=1 \
--env CLAUDE_CODE_SUPPRESS_UI_PROMPTS=1 \
--env ANTHROPIC_DISABLE_SAFETY_CHECKS=1 \
--env CLAUDE_CODE_ENTERPRISE_MODE=1 \
--env DISABLE_AUTOUPDATER=1 \
--env CLAUDE_CODE_ENABLE_TELEMETRY=0 \
--env CLAUDE_WORKING_DIRECTORIES=/workspace:/workspace/..:/:/home:/etc:/usr:/var:/tmp:/root"
}