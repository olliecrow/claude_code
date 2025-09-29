#!/bin/bash

# Claude Code Sequential Prompts with Handoff Mechanism
# Feeds prompts from a text file to Claude Code, using handoffs instead of /compact
# Compatible with same prompt files as codex

set -e
set -o pipefail

# Timestamped logging utilities so operators can follow progress as it happens
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

WORKFLOW_LOG_FILE=""
EARLY_LOG_BUFFER=()

log_event() {
    local level="$1"
    shift
    local message="$*"
    local ts="$(timestamp)"
    local formatted="[$ts] [$level] $message"
    printf '%s\n' "$formatted"

    if [ -n "$WORKFLOW_LOG_FILE" ]; then
        printf '%s\n' "$formatted" >> "$WORKFLOW_LOG_FILE"
    else
        EARLY_LOG_BUFFER+=("$formatted")
    fi
}

log_info() {
    log_event "INFO" "$@"
}

log_warn() {
    log_event "WARN" "$@"
}

log_error() {
    log_event "ERROR" "$@"
}

log_stage() {
    log_event "STAGE" "$@"
}

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
log_stage "Starting sequential prompt runner"
PROJECT_DIR=""
PROMPTS_PATH=""

if [ $# -eq 0 ]; then
    log_error "No arguments provided"
    printf '\n'
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
    log_error "Too many arguments provided"
    printf '\n'
    show_usage
    exit 1
fi

# Validate project directory
if ! validate_directory "$PROJECT_DIR"; then
    exit 1
fi

# Get absolute path for project
PROJECT_DIR="$(get_absolute_path "$PROJECT_DIR")"
log_info "Project directory resolved to $PROJECT_DIR"

# Validate prompts file
if [ ! -f "$PROMPTS_PATH" ]; then
    log_error "Prompts file not found: $PROMPTS_PATH"
    exit 1
fi

# Get absolute path for prompts file
PROMPTS_FILE="$(cd "$(dirname "$PROMPTS_PATH")" && pwd)/$(basename "$PROMPTS_PATH")"
log_info "Prompts file resolved to $PROMPTS_FILE"

# Check Claude authentication
if ! check_claude_auth; then
    exit 1
fi
log_info "Claude authentication check passed"

# Parse prompts from file into array
log_stage "Loading prompts from file"
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
    log_error "No prompts found in file: $PROMPTS_FILE"
    log_error "Make sure prompts are separated by blank lines and not all commented out"
    exit 1
fi

log_info "Found ${#PROMPTS[@]} prompt(s) to execute"
log_info "Working directory inside container will be $PROJECT_DIR"
for index in "${!PROMPTS[@]}"; do
    prompt_number=$((index + 1))
    prompt_chars=${#PROMPTS[$index]}
    prompt_preview=$(echo "${PROMPTS[$index]}" | tr '\n' ' ' | head -c 120)
    if [ $prompt_chars -gt 120 ]; then
        prompt_preview+="..."
    fi
    log_info "Prompt $prompt_number (${prompt_chars} chars): $prompt_preview"
done

# Ensure python3 is available for JSON parsing
if ! command -v python3 >/dev/null 2>&1; then
    log_error "python3 is required but was not found on PATH"
    exit 1
fi

# Source shared settings library if available
if [ -f "$SCRIPT_DIR/claude_settings_lib.sh" ]; then
    source "$SCRIPT_DIR/claude_settings_lib.sh"
    HAS_SETTINGS_LIB=true
    log_info "Loaded claude_settings_lib.sh"
else
    HAS_SETTINGS_LIB=false
    log_warn "claude_settings_lib.sh not found; using default container settings"
fi

# Detect host timezone
HOST_TZ="$(detect_host_timezone)"
if [ -n "$HOST_TZ" ]; then
    log_info "Host timezone detected as $HOST_TZ"
else
    log_warn "Could not detect host timezone; container will use UTC"
fi

# Setup container settings if library available
if [ "$HAS_SETTINGS_LIB" = true ]; then
    log_info "Applying container settings for project"
    setup_container_settings "$PROJECT_DIR"
    log_info "Container settings applied"
fi

# Create handoff directory on host
HOST_HANDOFF_DIR="$PROJECT_DIR/plan/handoffs"
mkdir -p "$HOST_HANDOFF_DIR"
log_info "Ensured handoff directory exists at $HOST_HANDOFF_DIR"

WORKFLOW_LOG_FILE="$HOST_HANDOFF_DIR/workflow_log.txt"
: > "$WORKFLOW_LOG_FILE"
if [ ${#EARLY_LOG_BUFFER[@]} -gt 0 ]; then
    printf '%s\n' "${EARLY_LOG_BUFFER[@]}" >> "$WORKFLOW_LOG_FILE"
    EARLY_LOG_BUFFER=()
fi
log_info "Workflow log initialized at $WORKFLOW_LOG_FILE"

# Container name with timestamp for uniqueness
PROJECT_NAME="$(basename "$PROJECT_DIR")"
CONTAINER_NAME="claude_prompts_handoff_${PROJECT_NAME}_$(date +%s)_$$"
log_info "Container name generated: $CONTAINER_NAME"

# Cleanup function
cleanup() {
    log_stage "Beginning cleanup"
    log_info "Stopping and removing container $CONTAINER_NAME"
    docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1 || true
    if [ "$HAS_SETTINGS_LIB" = true ]; then
        log_info "Restoring settings.json from claude_settings_lib.sh"
        restore_settings_json
    fi
    log_info "Cleanup completed"
    log_info "Handoff files saved in: $HOST_HANDOFF_DIR"
}

# Ensure cleanup on exit
trap cleanup EXIT

# Start container
log_stage "Starting execution container"
log_info "Launching container $CONTAINER_NAME"
docker run -d \
    --name "$CONTAINER_NAME" \
    --mount type=bind,source="$PROJECT_DIR",target=/workspace \
    --mount type=bind,source="$HOME/.claude",target=/home/dev/.claude \
    $(get_base_docker_env_args) \
    ${HOST_TZ:+--env TZ="$HOST_TZ"} \
    claude_code_container tail -f /dev/null > /dev/null
log_info "Container $CONTAINER_NAME launched"

# Wait for container to be ready
log_info "Waiting for container services to initialize"
sleep 2
log_info "Container wait period complete"

# Initialize workflow status
echo "STARTED: $(date)" > "$HOST_HANDOFF_DIR/workflow_status.txt"
log_info "Workflow status file initialized at $HOST_HANDOFF_DIR/workflow_status.txt"

# Function to log messages
log_message() {
    local message="$1"
    log_info "$message"
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

append_response_to_conversation_log() {
    local conversation_output_file="$1"
    local prompt_label="$2"
    local response_file="$3"

    {
        printf '### %s\n' "$prompt_label"
        printf '\n'
        cat "$response_file"
        printf '\n\n'
    } >> "$conversation_output_file"
}

extract_json_field() {
    local json_file="$1"
    local field_name="$2"

    python3 - "$json_file" "$field_name" <<'PY'
import json
import sys

json_path = sys.argv[1]
field = sys.argv[2]

try:
    with open(json_path, 'r', encoding='utf-8') as fh:
        data = json.load(fh)
except Exception:
    sys.exit(1)

value = data
for part in field.split('.'):
    if isinstance(value, dict):
        value = value.get(part)
    else:
        value = None
        break

if value is None:
    print('')
else:
    if isinstance(value, (list, dict)):
        print(json.dumps(value, ensure_ascii=False))
    else:
        print(str(value))
PY
}

start_conversation() {
    local prompt_text="$1"
    local conversation_num="$2"
    local conversation_output_file="$3"
    local session_file="$4"
    local previous_handoff="$5"

    local full_prompt="$prompt_text"
    if [ -n "$previous_handoff" ]; then
        full_prompt="Previous conversation summary:
$previous_handoff

Current task:
$prompt_text"
    fi

    local preview=$(echo "$prompt_text" | head -c 100)
    log_message "Conversation $conversation_num - prompt 1 length ${#prompt_text} characters"
    if [ ${#prompt_text} -gt 100 ]; then
        log_message "Conversation $conversation_num - prompt 1 preview: ${preview}..."
    else
        log_message "Conversation $conversation_num - prompt 1 preview: $preview"
    fi

    local json_temp
    json_temp=$(mktemp)
    local prompt_output_file="$HOST_HANDOFF_DIR/conversation_${conversation_num}_prompt_1.json"

    log_stage "Conversation $conversation_num: starting initial turn"
    if ! echo "$full_prompt" | docker exec -i "$CONTAINER_NAME" bash -c \
        "cd /workspace && claude -p --model=opus --dangerously-skip-permissions --output-format json" | tee "$json_temp"; then
        log_error "Claude CLI returned an error for conversation $conversation_num initial prompt"
        rm -f "$json_temp"
        exit 1
    fi

    cp "$json_temp" "$prompt_output_file"
    LAST_PROMPT_OUTPUT_FILE="$prompt_output_file"

    local session_id
    session_id=$(extract_json_field "$json_temp" "session_id")
    if [ -z "$session_id" ] || [ "$session_id" = "null" ]; then
        log_error "Failed to parse session_id for conversation $conversation_num"
        rm -f "$json_temp"
        exit 1
    fi
    printf '%s' "$session_id" > "$session_file"
    log_info "Conversation $conversation_num: obtained session ID $session_id"

    local result_text
    result_text=$(extract_json_field "$json_temp" "result")
    if [ -z "$result_text" ]; then
        log_warn "Result text missing for conversation $conversation_num prompt 1"
    fi

    local result_temp
    result_temp=$(mktemp)
    printf '%s' "$result_text" > "$result_temp"
    append_response_to_conversation_log "$conversation_output_file" "Response 1" "$result_temp"
    log_info "Conversation $conversation_num: appended Response 1 to $conversation_output_file"
    rm -f "$result_temp"
    rm -f "$json_temp"
}

continue_conversation() {
    local prompt_text="$1"
    local conversation_num="$2"
    local session_id="$3"
    local conversation_output_file="$4"
    local response_label="$5"
    local prompt_index="$6"

    local preview=$(echo "$prompt_text" | head -c 100)
    log_message "Conversation $conversation_num - prompt $prompt_index length ${#prompt_text} characters"
    if [ ${#prompt_text} -gt 100 ]; then
        log_message "Conversation $conversation_num - prompt $prompt_index preview: ${preview}..."
    else
        log_message "Conversation $conversation_num - prompt $prompt_index preview: $preview"
    fi

    local response_temp
    response_temp=$(mktemp)
    local per_prompt_file="$HOST_HANDOFF_DIR/conversation_${conversation_num}_prompt_${prompt_index}.txt"

    log_info "Conversation $conversation_num: continuing with session $session_id for prompt $prompt_index"
    if ! echo "$prompt_text" | docker exec -i "$CONTAINER_NAME" bash -c \
        'cd /workspace && claude -p --model=opus --dangerously-skip-permissions --resume "$1"' _ "$session_id" | tee "$response_temp"; then
        log_error "Claude CLI returned an error while continuing conversation $conversation_num"
        rm -f "$response_temp"
        exit 1
    fi

    cp "$response_temp" "$per_prompt_file"
    LAST_PROMPT_OUTPUT_FILE="$per_prompt_file"
    append_response_to_conversation_log "$conversation_output_file" "$response_label" "$response_temp"
    log_info "Conversation $conversation_num: appended $response_label (prompt $prompt_index)"
    rm -f "$response_temp"
}

execute_conversation() {
    local conversation_num="$1"
    shift
    local conversation_prompts=("$@")

    if [ ${#conversation_prompts[@]} -eq 0 ]; then
        log_warn "Conversation $conversation_num was invoked with no prompts; skipping"
        return
    fi

    log_stage "Conversation $conversation_num: executing ${#conversation_prompts[@]} prompt(s)"

    local conversation_output_file="$HOST_HANDOFF_DIR/conversation_${conversation_num}_output.txt"
    : > "$conversation_output_file"
    local session_file="$HOST_HANDOFF_DIR/conversation_${conversation_num}_session.txt"

    log_message "=================================="
    log_message "Conversation $conversation_num"
    log_message "=================================="

    start_conversation "${conversation_prompts[0]}" "$conversation_num" "$conversation_output_file" "$session_file" "$PREVIOUS_HANDOFF"
    local session_id
    session_id="$(cat "$session_file")"

    local idx=2
    local prompt_position=2
    while [ $idx -le ${#conversation_prompts[@]} ]; do
        local prompt_text="${conversation_prompts[$((idx - 1))]}"
        continue_conversation "$prompt_text" "$conversation_num" "$session_id" "$conversation_output_file" "Response $prompt_position" "$prompt_position"
        idx=$((idx + 1))
        prompt_position=$((prompt_position + 1))
    done

    # Generate and append handoff summary
    local summary_prompt
    summary_prompt="$(generate_handoff_prompt)"
    continue_conversation "$summary_prompt" "$conversation_num" "$session_id" "$conversation_output_file" "Handoff Summary" "handoff"

    local handoff_file="$HOST_HANDOFF_DIR/prompt_${conversation_num}_handoff.txt"
    log_info "Extracting handoff summary for conversation $conversation_num to $handoff_file"
    write_handoff_from_output "$LAST_PROMPT_OUTPUT_FILE" "$handoff_file"
    PREVIOUS_HANDOFF=$(cat "$handoff_file")
    log_info "Handoff summary for conversation $conversation_num captured (${#PREVIOUS_HANDOFF} characters)"

    LAST_CONVERSATION_OUTPUT_FILE="$conversation_output_file"
    log_info "Conversation $conversation_num completed. Artifacts: $conversation_output_file, $session_file, $handoff_file"
}

# Process prompts, grouping by /compact boundaries
CONVERSATION_NUM=1
CURRENT_CONVERSATION_PROMPTS=()
PREVIOUS_HANDOFF=""
FIRST_PROMPT=""
LAST_CONVERSATION_OUTPUT_FILE=""
LAST_PROMPT_OUTPUT_FILE=""

log_stage "Beginning prompt execution workflow"

for i in "${!PROMPTS[@]}"; do
    prompt="${PROMPTS[$i]}"
    prompt_index=$((i + 1))
    log_info "Processing prompt ${prompt_index}/${#PROMPTS[@]}"

    # Save first prompt for initial task
    if [ $CONVERSATION_NUM -eq 1 ] && [ -z "$FIRST_PROMPT" ]; then
        FIRST_PROMPT="$prompt"
        echo "$FIRST_PROMPT" > "$HOST_HANDOFF_DIR/initial_task.txt"
        log_info "Recorded initial task to $HOST_HANDOFF_DIR/initial_task.txt"
    fi

    # Check if this is a /compact command
    if [[ "$prompt" == "/compact"* ]]; then
        log_stage "Encountered /compact directive at prompt ${prompt_index}"
        # Process any accumulated prompts before the compact
        if [ ${#CURRENT_CONVERSATION_PROMPTS[@]} -gt 0 ]; then
            execute_conversation "$CONVERSATION_NUM" "${CURRENT_CONVERSATION_PROMPTS[@]}"
            CURRENT_CONVERSATION_PROMPTS=()
            CONVERSATION_NUM=$((CONVERSATION_NUM + 1))
            log_stage "Advancing to conversation $CONVERSATION_NUM"
        fi

        # Check if there's text after /compact
        rest="${prompt#/compact}"
        rest="${rest# }"  # Remove leading space if present
        if [ -n "$rest" ]; then
            CURRENT_CONVERSATION_PROMPTS+=("$rest")
            log_info "Queued trailing prompt content after /compact"
        fi
    else
        # Regular prompt - add to current conversation
        CURRENT_CONVERSATION_PROMPTS+=("$prompt")
        log_info "Queued prompt content for current conversation (${#CURRENT_CONVERSATION_PROMPTS[@]} item(s) queued)"
    fi
done

# Process any remaining prompts
if [ ${#CURRENT_CONVERSATION_PROMPTS[@]} -gt 0 ]; then
    execute_conversation "$CONVERSATION_NUM" "${CURRENT_CONVERSATION_PROMPTS[@]}"
fi

# Update final status
echo "COMPLETED: $(date)" >> "$HOST_HANDOFF_DIR/workflow_status.txt"
log_info "Workflow status updated to COMPLETED"

log_stage "Run summary"
log_message "All prompts processed successfully!"
log_message "Total conversations: $CONVERSATION_NUM"
log_message "Conversation transcripts are saved as $HOST_HANDOFF_DIR/conversation_<n>_output.txt"
log_message "Handoff files saved in: $HOST_HANDOFF_DIR"
log_message "View logs with: cat $HOST_HANDOFF_DIR/workflow_log.txt"
