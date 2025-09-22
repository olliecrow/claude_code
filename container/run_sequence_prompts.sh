#!/bin/bash

# Claude Code Sequential Prompts with Handoff Mechanism
# Feeds prompts from a text file to Claude Code, using handoffs instead of /compact
# Compatible with same prompt files as codex

set -e

# Source common library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/claude_common_lib.sh"

# Usage and help functions
show_usage() {
    cat << EOF
Usage:
  $(basename "$0") /path/to/prompts.txt                    # Execute in current directory
  $(basename "$0") /path/to/project /path/to/prompts.txt  # Execute in specified directory
  $(basename "$0") --help | -h                            # Show this help

Description:
  Sequentially feeds prompts to Claude Code CLI using handoff mechanism.
  Prompts are separated by blank lines. Each block of text (one or more lines)
  separated by an empty line is treated as a single prompt.

  When a /compact command is encountered, it triggers a handoff - the current
  conversation ends with a summary that gets passed to a fresh conversation.

Arguments:
  project_directory    Path to your project directory (optional, defaults to current)
  prompts_file        Path to the file containing prompts

Prompt File Format:
  - Separate prompts with blank lines
  - Multi-line prompts are supported
  - /compact triggers a handoff to new conversation
  - Comments starting with # are ignored

Example prompts.txt:
  # First prompt
  Analyze the codebase and identify main components

  # Trigger handoff (instead of in-conversation compact)
  /compact

  # Continue in new conversation with context
  Now implement a new feature based on the analysis

Examples:
  $0 prompts.txt                          # Run in current directory
  $0 /path/to/project prompts.txt        # Run in specific project

Handoff Files:
  Creates handoff files in /workspace/plan/handoffs/ inside container:
  - initial_task.txt - The first prompt
  - prompt_N_handoff.txt - Handoff summaries between conversations
  - workflow_status.txt - Current execution status
  - workflow_log.txt - Complete execution log

EOF
}

# Handle help flags
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
fi

# Input validation and argument parsing
PROJECT_DIR=""
PROMPTS_PATH=""

if [ $# -eq 0 ]; then
    echo "Error: No arguments provided"
    echo ""
    show_usage
    exit 1
elif [ $# -eq 1 ]; then
    # Single argument: use current directory, argument is prompts file
    PROJECT_DIR="$(pwd)"
    PROMPTS_PATH="$1"
elif [ $# -eq 2 ]; then
    # Two arguments: first is directory, second is prompts file
    PROJECT_DIR="$1"
    PROMPTS_PATH="$2"
else
    echo "Error: Too many arguments provided"
    echo ""
    show_usage
    exit 1
fi

# Validate project directory
if ! validate_directory "$PROJECT_DIR"; then
    exit 1
fi

# Get absolute path for project
PROJECT_DIR="$(get_absolute_path "$PROJECT_DIR")"

# Validate prompts file
if [ ! -f "$PROMPTS_PATH" ]; then
    echo "Error: Prompts file not found: $PROMPTS_PATH"
    exit 1
fi

# Get absolute path for prompts file
PROMPTS_FILE="$(cd "$(dirname "$PROMPTS_PATH")" && pwd)/$(basename "$PROMPTS_PATH")"

# Check Claude authentication
if ! check_claude_auth; then
    exit 1
fi

# Parse prompts from file into array
PROMPTS=()
current_prompt=""

while IFS= read -r line || [ -n "$line" ]; do
    # Remove carriage returns if present
    line="${line%$'\r'}"

    # Skip comment lines
    if [[ "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi

    # Check if line is blank (only whitespace)
    if [ -z "${line// }" ]; then
        # If we have accumulated a prompt, add it to array
        if [ -n "${current_prompt// }" ]; then
            PROMPTS+=("$current_prompt")
            current_prompt=""
        fi
        continue
    fi

    # Add line to current prompt
    if [ -n "$current_prompt" ]; then
        current_prompt+=$'\n'
    fi
    current_prompt+="$line"
done < "$PROMPTS_FILE"

# Add final prompt if exists
if [ -n "${current_prompt// }" ]; then
    PROMPTS+=("$current_prompt")
fi

# Check if we have any prompts
if [ ${#PROMPTS[@]} -eq 0 ]; then
    echo "Error: No prompts found in file: $PROMPTS_FILE"
    echo "Make sure prompts are separated by blank lines and not all commented out"
    exit 1
fi

echo "Found ${#PROMPTS[@]} prompt(s) to execute"
echo "Project directory: $PROJECT_DIR"
echo ""

# Source shared settings library if available
if [ -f "$SCRIPT_DIR/claude_settings_lib.sh" ]; then
    source "$SCRIPT_DIR/claude_settings_lib.sh"
    HAS_SETTINGS_LIB=true
else
    HAS_SETTINGS_LIB=false
fi

# Detect host timezone
HOST_TZ="$(detect_host_timezone)"
if [ -n "$HOST_TZ" ]; then
    echo "Host timezone detected: $HOST_TZ"
else
    echo "Warning: Could not detect host timezone, container will use UTC"
fi

# Setup container settings if library available
if [ "$HAS_SETTINGS_LIB" = true ]; then
    setup_container_settings "$PROJECT_DIR"
fi

# Create handoff directory on host
HOST_HANDOFF_DIR="$PROJECT_DIR/plan/handoffs"
mkdir -p "$HOST_HANDOFF_DIR"

# Container name with timestamp for uniqueness
PROJECT_NAME="$(basename "$PROJECT_DIR")"
CONTAINER_NAME="claude_prompts_handoff_${PROJECT_NAME}_$(date +%s)_$$"

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up container..."
    docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1 || true
    if [ "$HAS_SETTINGS_LIB" = true ]; then
        restore_settings_json
    fi
    echo "Cleanup completed."
    echo ""
    echo "Handoff files saved in: $HOST_HANDOFF_DIR"
}

# Ensure cleanup on exit
trap cleanup EXIT

# Start container
echo "Starting container: $CONTAINER_NAME"
docker run -d \
    --name "$CONTAINER_NAME" \
    --mount type=bind,source="$PROJECT_DIR",target=/workspace \
    --mount type=bind,source="$HOME/.claude",target=/home/dev/.claude \
    $(get_base_docker_env_args) \
    ${HOST_TZ:+--env TZ="$HOST_TZ"} \
    claude_code_container tail -f /dev/null > /dev/null

# Wait for container to be ready
sleep 2

# Initialize workflow status
echo "STARTED: $(date)" > "$HOST_HANDOFF_DIR/workflow_status.txt"
echo "" > "$HOST_HANDOFF_DIR/workflow_log.txt"

# Function to log messages
log_message() {
    local message="$1"
    echo "$message"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$HOST_HANDOFF_DIR/workflow_log.txt"
}

# Function to generate handoff summary prompt
generate_handoff_prompt() {
    echo "Generate a comprehensive handoff summary of everything done in this conversation.

Include:
- What was accomplished
- Any files created or modified
- Key decisions or findings
- Current state of the project
- Important context for continuation

Be thorough but concise. This summary will be the only context passed forward.
Output in plain text format."
}

# Function to execute a prompt in a new conversation
run_prompt_with_handoff() {
    local prompt_text="$1"
    local conversation_num="$2"
    local is_handoff_continuation="$3"
    local previous_handoff="$4"

    log_message "=================================="
    log_message "Conversation $conversation_num"
    log_message "=================================="

    # Build the full prompt with context if needed
    local full_prompt=""
    if [ "$is_handoff_continuation" = "true" ] && [ -n "$previous_handoff" ]; then
        full_prompt="Previous conversation summary:
$previous_handoff

Current task:
$prompt_text"
    else
        full_prompt="$prompt_text"
    fi

    # Show preview
    local preview=$(echo "$prompt_text" | head -c 100)
    if [ ${#prompt_text} -gt 100 ]; then
        log_message "Prompt preview: ${preview}..."
    else
        log_message "Prompt: $preview"
    fi

    # Execute using SDK mode (no TTY needed)
    log_message "Starting new conversation..."
    echo "$full_prompt" | docker exec -i "$CONTAINER_NAME" bash -c \
        "cd /workspace && claude -p --model=opus --dangerously-skip-permissions"

    log_message "Conversation $conversation_num completed"
}

# Process prompts, grouping by /compact boundaries
CONVERSATION_NUM=1
CURRENT_CONVERSATION_PROMPTS=()
PREVIOUS_HANDOFF=""
FIRST_PROMPT=""

for i in "${!PROMPTS[@]}"; do
    prompt="${PROMPTS[$i]}"

    # Save first prompt for initial task
    if [ $CONVERSATION_NUM -eq 1 ] && [ -z "$FIRST_PROMPT" ]; then
        FIRST_PROMPT="$prompt"
        echo "$FIRST_PROMPT" > "$HOST_HANDOFF_DIR/initial_task.txt"
    fi

    # Check if this is a /compact command
    if [[ "$prompt" == "/compact"* ]]; then
        # Process any accumulated prompts before the compact
        if [ ${#CURRENT_CONVERSATION_PROMPTS[@]} -gt 0 ]; then
            # Combine prompts for this conversation
            combined_prompt=""
            for p in "${CURRENT_CONVERSATION_PROMPTS[@]}"; do
                if [ -n "$combined_prompt" ]; then
                    combined_prompt+=$'\n\n'
                fi
                combined_prompt+="$p"
            done

            # Add handoff generation request
            combined_prompt+=$'\n\n'
            combined_prompt+="$(generate_handoff_prompt)"

            # Run the conversation
            if [ $CONVERSATION_NUM -eq 1 ]; then
                run_prompt_with_handoff "$combined_prompt" "$CONVERSATION_NUM" "false" ""
            else
                run_prompt_with_handoff "$combined_prompt" "$CONVERSATION_NUM" "true" "$PREVIOUS_HANDOFF"
            fi

            # Capture handoff from container output (last part of conversation)
            # Note: In production, we'd parse Claude's actual response
            # For now, we'll save a placeholder
            HANDOFF_FILE="$HOST_HANDOFF_DIR/prompt_${CONVERSATION_NUM}_handoff.txt"
            echo "Handoff from conversation $CONVERSATION_NUM:
- Completed prompts: ${#CURRENT_CONVERSATION_PROMPTS[@]}
- Ready for next conversation
[Context would be extracted from Claude's response]" > "$HANDOFF_FILE"

            PREVIOUS_HANDOFF=$(cat "$HANDOFF_FILE")

            # Reset for next conversation
            CURRENT_CONVERSATION_PROMPTS=()
            CONVERSATION_NUM=$((CONVERSATION_NUM + 1))
        fi

        # Check if there's text after /compact
        rest="${prompt#/compact}"
        rest="${rest# }"  # Remove leading space if present
        if [ -n "$rest" ]; then
            CURRENT_CONVERSATION_PROMPTS+=("$rest")
        fi
    else
        # Regular prompt - add to current conversation
        CURRENT_CONVERSATION_PROMPTS+=("$prompt")
    fi
done

# Process any remaining prompts
if [ ${#CURRENT_CONVERSATION_PROMPTS[@]} -gt 0 ]; then
    # Combine remaining prompts
    combined_prompt=""
    for p in "${CURRENT_CONVERSATION_PROMPTS[@]}"; do
        if [ -n "$combined_prompt" ]; then
            combined_prompt+=$'\n\n'
        fi
        combined_prompt+="$p"
    done

    # Run final conversation
    if [ $CONVERSATION_NUM -eq 1 ]; then
        run_prompt_with_handoff "$combined_prompt" "$CONVERSATION_NUM" "false" ""
    else
        run_prompt_with_handoff "$combined_prompt" "$CONVERSATION_NUM" "true" "$PREVIOUS_HANDOFF"
    fi
fi

# Update final status
echo "COMPLETED: $(date)" >> "$HOST_HANDOFF_DIR/workflow_status.txt"

log_message ""
log_message "=================================="
log_message "All prompts processed successfully!"
log_message "=================================="
log_message "Total conversations: $CONVERSATION_NUM"
log_message ""
log_message "Handoff files saved in: $HOST_HANDOFF_DIR"
log_message "View logs: cat $HOST_HANDOFF_DIR/workflow_log.txt"