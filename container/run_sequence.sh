#!/bin/bash

# Claude Code Sequential Workflow Executor
# Runs a predefined sequence of stages inside the Claude Code container
# Maintains session context across all stages for continuity

set -e

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Error: Please specify a project directory and initial task"
    echo "Usage: $0 /path/to/project \"Your initial task\""
    echo "Example: $0 /path/to/project \"Build a beautiful calculator app similar to iPhone\""
    exit 1
fi

REPO_DIR="$1"
INITIAL_TASK="${2:-}"

# If only one argument, treat it as the initial task and use current directory
if [ $# -eq 1 ] && [ ! -d "$1" ]; then
    REPO_DIR="$(pwd)"
    INITIAL_TASK="$1"
fi

# Verify directory exists
if [ ! -d "$REPO_DIR" ]; then
    echo "Error: Directory '$REPO_DIR' does not exist"
    exit 1
fi

# Get absolute path
REPO_DIR="$(cd "$REPO_DIR" && pwd)"

# Check if Claude authentication exists
if [ ! -d "$HOME/.claude" ]; then
    echo "Error: No Claude authentication found"
    echo "Please run 'claude' first and complete authentication"
    exit 1
fi

# Source shared settings library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/claude_settings_lib.sh" ]; then
    source "$SCRIPT_DIR/claude_settings_lib.sh"
    HAS_SETTINGS_LIB=true
else
    HAS_SETTINGS_LIB=false
fi

# Generate a session ID for tracking (even though we use -c for continuation)
SESSION_ID=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "session-$$-$(date +%s)")

echo "=================================="
echo "Claude Code Sequential Workflow [DEBUG MODE]"
echo "=================================="
echo "Project: $REPO_DIR"
echo "Initial task: $INITIAL_TASK"
echo "Session ID: $SESSION_ID (for tracking)"
echo "Starting container..."
echo ""

# Setup container settings if library available
if [ "$HAS_SETTINGS_LIB" = true ]; then
    setup_container_settings "$REPO_DIR"
fi

# Container name
CONTAINER_NAME="claude_sequence_$(basename "$REPO_DIR")_$$"

# Function to cleanup container and settings
cleanup() {
    echo ""
    echo "Cleaning up..."
    docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1 || true
    if [ "$HAS_SETTINGS_LIB" = true ]; then
        restore_settings_json 2>/dev/null || true
    fi
}

# Ensure cleanup on exit
trap cleanup EXIT

# Start container in detached mode
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
    --env CLAUDE_SESSION_ID="$SESSION_ID" \
    claude_code_container tail -f /dev/null > /dev/null 2>&1

# Wait for container to be ready
sleep 2

# DEBUG MODE - Using dummy commands for testing
# To restore production mode, uncomment the PRODUCTION sections and comment out DEBUG sections

# ============= DEBUG STAGES =============
# Simple test stages that just list files and show environment
# STAGES=(
#     "test_1"
#     "test_2"
#     "test_3"
#     "summary"
# )

# # Define prompts using a function for compatibility with older bash
# get_prompt() {
#     case "$1" in
#         "test_1") echo "/joke List all files in the current directory. Output all jokes so far in your context into a file called joke_0.txt" ;;
#         "test_2") echo "/joke Show the current working directory and date. Output all jokes so far in your context into a file called joke_1.txt" ;;
#         "test_3") echo "/joke Create a test file called debug_test.txt with the session ID in it. Output all jokes so far in your context into a file called joke_2.txt" ;;
#         "summary") echo "Summarize all jokes so far in your context into a file called joke_summary.txt" ;;
#     esac
# }

# ============= PRODUCTION STAGES (COMMENTED OUT) =============
STAGES=(
    "investigate"
    "plan"
    "plan"
    "execute"
    "execute"
    "execute"
    "execute"
    "execute"
    "verify"
    "verify"
    "cleanup"
    "summary"
)

get_prompt() {
    case "$1" in
        "investigate") echo "/plan conduct deep and thorough investigations, research, testing, debugging, etc on the task at hand. do not plan/execute yet, just investigate/research. dont hesitate to use standalone/debugging scripts & add print lines during this task if helpful. update your planning/markdown file(s). use many agents." ;;
        "plan") echo "/plan create a detailed plan for the task at hand. ensure that there is defined scope, no ambiguity, and no chance for overly complex solutions or overengineering. do not execute yet, just plan. dont hesitate to use standalone/debugging scripts & add print lines during this task if helpful. update your planning/markdown file(s). use many agents." ;;
        "compact") echo "/compact remember everything so far in verbose detail. list the names/locations of all planning/markdown file(s) relevant in this conversation specifically." ;;
        "execute") echo "/plan execute the plan. if there is nothing left to do (within the plan and scope), then just return (do nothing). if there are remaining items, lets keep going. dont hesitate to use standalone/debugging scripts & add print lines during this task if helpful. update your planning/markdown file(s). use many agents." ;;
        "verify") echo "/plan verify that all tasks in the plan are complete, through whatever means and methods required to verify and validate. dont hesitate to use standalone/debugging scripts & add print lines during this task if helpful. update your planning/markdown file(s). use many agents." ;;
        "cleanup") echo "/plan conduct a deep and thorough cleanup of the project. remove all files and directories that are no longer needed." ;;
        "summary") echo "/plan summarize this conversation so far. output the summary here (not into a file)." ;;
    esac
}

# Function to execute a stage
execute_stage() {
    local stage_name="$1"
    local stage_num="$2"
    local total_stages="$3"
    local is_first="$4"
    
    # Get the prompt for this stage
    local stage_prompt=$(get_prompt "$stage_name")
    
    echo "=================================="
    echo "Stage $stage_num/$total_stages: $stage_name  [DEBUG MODE]"
    echo "Session: $SESSION_ID"
    echo "=================================="
    
    # Build the command
    if [ "$is_first" = "true" ]; then
        # First stage creates a new session and includes the initial task
        # Stage prompt always comes first, then the task
        local full_prompt="$stage_prompt

Task: $INITIAL_TASK"
        # First command creates the session
        local claude_cmd="claude --dangerously-skip-permissions"
        echo "Creating new conversation..."
    else
        # Subsequent stages continue the conversation with -c flag
        local full_prompt="$stage_prompt"
        local claude_cmd="claude -c --dangerously-skip-permissions"
        echo "Continuing conversation with -c flag..."
    fi
    
    # Execute the command inside the container (no timeout)
    echo "Executing stage..."
    
    # Use a temporary file inside the container for the prompt to avoid escaping issues
    docker exec "$CONTAINER_NAME" bash -c "cat > /tmp/prompt_$stage_name.txt << 'EOF'
$full_prompt
EOF"
    
    # Execute Claude with the prompt file
    docker exec "$CONTAINER_NAME" bash -c "cd /workspace && cat /tmp/prompt_$stage_name.txt | $claude_cmd"
    local exit_code=$?
    
    # Clean up the prompt file
    docker exec "$CONTAINER_NAME" rm -f "/tmp/prompt_$stage_name.txt" 2>/dev/null || true
    
    if [ $exit_code -ne 0 ]; then
        echo "Warning: Stage $stage_name exited with code $exit_code"
        # Try to continue anyway for robustness
        return 0
    fi
    
    echo "Stage $stage_name completed successfully"
    echo ""
    
    # Small delay between stages for stability
    sleep 2
    
    return 0
}

# Execute all stages
TOTAL_STAGES=${#STAGES[@]}
STAGE_NUM=1

for i in "${!STAGES[@]}"; do
    STAGE="${STAGES[$i]}"
    
    if [ $i -eq 0 ]; then
        IS_FIRST="true"
    else
        IS_FIRST="false"
    fi
    
    execute_stage "$STAGE" "$STAGE_NUM" "$TOTAL_STAGES" "$IS_FIRST"
    
    STAGE_NUM=$((STAGE_NUM + 1))
done

echo "=================================="
echo "Workflow Complete!"
echo "=================================="
echo "Session ID: $SESSION_ID"
echo "All stages executed successfully"
echo ""
echo "You can continue this conversation with:"
echo "  docker exec -it $CONTAINER_NAME claude -c"
echo "Or start a new container session with:"
echo "  ./run.sh $REPO_DIR"
echo ""