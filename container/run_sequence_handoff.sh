#!/bin/bash

# Claude Code Sequential Workflow with Context Handoffs
# Each stage runs as a separate conversation with structured summaries passed between

set -e

# Usage and help functions
show_usage() {
    cat << EOF
Usage: 
  $0 <initial_task>                    # Execute in current directory
  $0 <project_directory> <initial_task> # Execute in specified directory
  $0 --help | -h                      # Show this help

Description:
  Runs a multi-stage Claude Code workflow with context handoffs.
  Each stage runs as a separate conversation with structured summaries.

Arguments:
  project_directory    Path to your project directory (optional, defaults to current)
  initial_task        Description of the task to complete (supports multi-line)

Examples:
  $0 "Analyze and fix test suite"
  $0 /path/to/project "Build a calculator app"
  $0 ~/myproject "Review code and suggest improvements"

Monitoring:
  - Watch terminal output for real-time progress
  - Check /workspace/plan/handoffs/ for stage files and status

Files Created:
  /workspace/plan/handoffs/workflow_status.txt    # Current status
  /workspace/plan/handoffs/workflow_log.txt       # Complete log
  /workspace/plan/handoffs/stage_N_handoff.txt    # Stage summaries
EOF
}

# Handle help flags
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    show_usage
    exit 0
fi

# Input validation and argument parsing
if [ $# -eq 0 ]; then
    echo "Error: No arguments provided"
    echo ""
    show_usage
    exit 1
elif [ $# -eq 1 ]; then
    # Single argument: use current directory, argument is task
    if [ -z "$1" ]; then
        echo "Error: Initial task cannot be empty"
        echo ""
        show_usage
        exit 1
    fi
    REPO_DIR="$(pwd)"
    INITIAL_TASK="$1"
elif [ $# -eq 2 ]; then
    # Two arguments: first is directory, second is task
    if [ -z "$1" ]; then
        echo "Error: Project directory cannot be empty"
        echo ""
        show_usage
        exit 1
    fi
    if [ -z "$2" ]; then
        echo "Error: Initial task cannot be empty"
        echo ""
        show_usage
        exit 1
    fi
    if [ ! -d "$1" ]; then
        echo "Error: Directory '$1' does not exist"
        exit 1
    fi
    REPO_DIR="$(cd "$1" && pwd)"  # Get absolute path
    INITIAL_TASK="$2"
else
    echo "Error: Too many arguments provided"
    echo ""
    show_usage
    exit 1
fi
SESSION_ID=$(uuidgen 2>/dev/null || echo "session-$$-$(date +%s)")

# Host-side paths (for file operations on host)
HOST_PLAN_DIR="$REPO_DIR/plan"
HOST_HANDOFF_DIR="$HOST_PLAN_DIR/handoffs"

# Container-side paths (for referencing inside container)
CONTAINER_HANDOFF_DIR="/workspace/plan/handoffs"
STATUS_FILE="$HOST_HANDOFF_DIR/workflow_status.txt"
LOG_FILE="$HOST_HANDOFF_DIR/workflow_log.txt"

# Create plan directory structure on host (will be mounted as /workspace/plan in container)
mkdir -p "$HOST_PLAN_DIR"

# Logging function with timestamps
log_with_timestamp() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Create fresh handoff directory (cleanup previous runs)
if [ -d "$HOST_HANDOFF_DIR" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🧹 Cleaning up previous handoff directory..."
    rm -rf "$HOST_HANDOFF_DIR"/*
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Previous handoffs cleared"
fi
mkdir -p "$HOST_HANDOFF_DIR"

# Initialize tracking files
echo "Workflow started at $(date)" > "$LOG_FILE"
echo "WORKFLOW_STATUS=INITIALIZING" > "$STATUS_FILE"
log_with_timestamp "📁 Fresh handoff directory created: $HOST_HANDOFF_DIR"

# Update workflow status
update_workflow_status() {
    local status="$1"
    local current_stage="${2:-}"
    local details="${3:-}"
    
    echo "WORKFLOW_STATUS=$status" > "$STATUS_FILE"
    echo "CURRENT_STAGE=$current_stage" >> "$STATUS_FILE"
    echo "SESSION_ID=$SESSION_ID" >> "$STATUS_FILE"
    echo "LAST_UPDATE=$(date)" >> "$STATUS_FILE"
    if [ -n "$details" ]; then
        echo "DETAILS=$details" >> "$STATUS_FILE"
    fi
    
    log_with_timestamp "Status updated: $status ${current_stage:+- Stage: $current_stage} ${details:+- $details}"
}

# Simple retry mechanism for Claude operations
retry_claude_operation() {
    local operation_description="$1"
    local operation_command="$2"
    local max_retries=1  # One retry as requested
    
    for attempt in 1 2; do
        log_with_timestamp "🔄 $operation_description (attempt $attempt)"
        
        if eval "$operation_command"; then
            if [ $attempt -eq 2 ]; then
                log_with_timestamp "✅ $operation_description succeeded on retry"
            fi
            return 0  # Success
        else
            local exit_code=$?
            if [ $attempt -le $max_retries ]; then
                log_with_timestamp "⚠️  $operation_description failed (attempt $attempt), retrying in 5 seconds..."
                sleep 5
            else
                log_with_timestamp "❌ $operation_description failed after $max_retries retry (exit code: $exit_code)"
                return $exit_code
            fi
        fi
    done
}

log_with_timestamp "=================================="
log_with_timestamp "Claude Code Handoff Workflow STARTED"
log_with_timestamp "=================================="
log_with_timestamp "Project: $REPO_DIR"
log_with_timestamp "Session ID: $SESSION_ID"
log_with_timestamp "Handoff Dir: $HOST_HANDOFF_DIR"
log_with_timestamp "Status File: $STATUS_FILE"
log_with_timestamp "Log File: $LOG_FILE"
log_with_timestamp ""

update_workflow_status "STARTING" "" "Initializing workflow components"

# STAGES=(
#     "investigate"
#     "plan"
#     "plan" 
#     "execute"
#     "execute"
#     "execute"
#     "execute"
#     "verify"
#     "verify"
#     "cleanup"
#     "summary"
# )

STAGES=(
    "test_joke"
    "test_joke"
    "test_joke"
)

# Rolling handoff prompt - consolidates all prior work into current summary
generate_handoff_prompt() {
    local stage_name="$1"
    local stage_num="$2"
    echo "/plan Save all information from this chat into your markdown plan file(s), then generate a comprehensive handoff summary.

IMPORTANT: Before writing your summary, examine the handoff directory at /workspace/plan/handoffs/ and read ALL prior stage handoff files (stage_1_handoff.txt, stage_2_handoff.txt, etc.) to understand the complete workflow context.

Your handoff summary should consolidate:
1. ALL essential information from the original task
2. ALL work completed in previous stages (from prior handoffs)  
3. ALL work completed in this current stage (from this chat)

Include:

## Consolidated Workflow Summary: $stage_name (Stage $stage_num)

## Complete Task Context
- Original task and requirements
- All work completed across ALL stages so far
- All project files created, modified, or deleted (all stages)
- All plan/markdown/txt/etc files created, modified, or deleted (all stages)
- All critical decisions made throughout workflow
- Any blockers or issues encountered (any stage)
- Maintain a timelines across all stages.

## Current Workflow State
- Complete status of the main task/objective
- All relevant files and directories from entire workflow
- All intermediate results and findings so far
- Progress made across all stages

## For Next Stage
- What the next stage should focus on
- Any specific requirements or constraints
- Files/directories they should examine first
- Complete context needed to continue the work
- If workflow is complete, clearly state this

## Instructions
- This summary will be the ONLY context passed to the next stage
- Include everything important from the entire workflow so far
- No word limit - be as comprehensive as needed
- Focus on actionable information and concrete results
- Include specific file paths and complete status
- This is a rolling summary - each stage builds on all previous work

Output this consolidated handoff summary in plain text (not markdown) for easy parsing."
}

# Build context prompt from most recent handoff only (rolling summary approach)
build_context_from_handoffs() {
    local current_stage_num="$1"
    local context=""
    
    # For Stage 1, only provide original task
    if [ "$current_stage_num" -eq 1 ]; then
        if [ -f "$HOST_HANDOFF_DIR/initial_task.txt" ]; then
            context="## Original Task
$(cat "$HOST_HANDOFF_DIR/initial_task.txt")

"
        fi
    else
        # For Stage 2+, only provide the most recent handoff (which contains all consolidated info)
        local most_recent_stage=$((current_stage_num - 1))
        local most_recent_handoff="$HOST_HANDOFF_DIR/stage_${most_recent_stage}_handoff.txt"
        
        if [ -f "$most_recent_handoff" ]; then
            context="## Previous Stage Summary (All Workflow Context)
$(cat "$most_recent_handoff")

"
        else
            # Fallback to original task if no prior handoff exists
            if [ -f "$HOST_HANDOFF_DIR/initial_task.txt" ]; then
                context="## Original Task
$(cat "$HOST_HANDOFF_DIR/initial_task.txt")

"
            fi
        fi
    fi
    
    echo "$context"
}

# Common prompt fragments to avoid repetition
DEBUG_HELP="dont hesitate to use standalone/debugging scripts & add print lines during this task if helpful."
UPDATE_DOCS="update your planning/markdown file(s)."
USE_AGENTS="use many agents."
PLAN_SUFFIX="$DEBUG_HELP $UPDATE_DOCS $USE_AGENTS"

# Get which iteration of this stage type we're at
get_stage_iteration() {
    local stage_name="$1"
    local current_stage_num="$2"
    local iteration=1
    
    for ((i=0; i<current_stage_num-1; i++)); do
        if [ "${STAGES[$i]}" = "$stage_name" ]; then
            ((iteration++))
        fi
    done
    
    echo "$iteration"
}

# Get stage-specific prompt
get_stage_prompt() {
    local stage_name="$1"
    local stage_num="$2"
    local iteration=$(get_stage_iteration "$stage_name" "$stage_num")
    
    # case "$stage_name" in
    #     "investigate") echo "/plan conduct deep and thorough investigations, research, testing, debugging, etc on the task at hand. do not plan/execute yet, just investigate/research. $PLAN_SUFFIX" ;;
    #     "plan") echo "/plan create / continue to flesh out the plan. ensure that there is defined scope, no ambiguity, and no chance for overly complex solutions or overengineering. do not execute yet, just plan. This is plan iteration $iteration. $PLAN_SUFFIX" ;;
    #     "compact") echo "/compact remember everything so far in verbose detail. list the names/locations of all planning/markdown file(s) relevant in this conversation specifically." ;;
    #     "execute") echo "/plan execute the plan. if there is nothing left to do (within the plan and scope), then just return (do nothing). if there are remaining items, lets keep going. This is execute iteration $iteration. $PLAN_SUFFIX" ;;
    #     "verify") echo "/plan verify that all tasks in the plan are complete, through whatever means and methods required to verify and validate. This is verify iteration $iteration. $PLAN_SUFFIX" ;;
    #     "cleanup") echo "/plan conduct a deep and thorough cleanup of the project. remove all files and directories that are no longer needed." ;;
    #     "summary") echo "/plan summarize this conversation so far. output the summary here (not into a file)." ;;
    # esac
    case "$stage_name" in
        "test_joke") echo "/joke Create a test file called debug_test.txt with the session ID in it. Output all jokes so far in your context into a file unique to this stage.txt" ;;
    esac
}

# Execute a single stage with handoff
execute_stage_with_handoff() {
    local stage_name="$1"
    local stage_num="$2"
    local total_stages="$3"
    local stage_start_time=$(date +%s)
    
    log_with_timestamp "=================================="
    log_with_timestamp "STAGE $stage_num/$total_stages: $stage_name"
    log_with_timestamp "Session: $SESSION_ID"
    log_with_timestamp "Start time: $(date)"
    log_with_timestamp "=================================="
    
    update_workflow_status "STAGE_STARTING" "$stage_name" "Stage $stage_num of $total_stages"
    
    log_with_timestamp "🔍 Building context from previous handoffs..."
    # Build context from previous handoffs
    local context=$(build_context_from_handoffs "$stage_num")
    local context_length=$(echo "$context" | wc -w)
    log_with_timestamp "📝 Context built: $context_length words from previous stages"
    
    log_with_timestamp "🎯 Generating stage-specific prompt for: $stage_name"
    local stage_prompt=$(get_stage_prompt "$stage_name" "$stage_num")
    
    # Create full prompt with SLASH COMMAND FIRST, then context
    local full_prompt="$stage_prompt

## Context from Previous Stages
$context"
    
    local prompt_length=$(echo "$full_prompt" | wc -w)
    log_with_timestamp "📄 Full prompt created: $prompt_length total words"
    
    # Save prompt to file for debugging
    local prompt_file="$HOST_HANDOFF_DIR/stage_${stage_num}_prompt.txt"
    echo "$full_prompt" > "$prompt_file"
    log_with_timestamp "💾 Prompt saved to: $prompt_file"
    
    log_with_timestamp "🚀 EXECUTING STAGE $stage_name..."
    update_workflow_status "STAGE_EXECUTING" "$stage_name" "Claude processing stage $stage_num"
    
    # Execute stage (NEW conversation each time - no -c flag)
    log_with_timestamp "📤 Sending prompt to Claude container..."
    docker exec "$CONTAINER_NAME" bash -c "cat > /tmp/stage_prompt.txt << 'EOF'
$full_prompt
EOF"
    
    # Run the stage with retry mechanism
    log_with_timestamp "⚡ Claude is processing stage $stage_name..."
    local claude_start_time=$(date +%s)
    retry_claude_operation "Claude stage execution for $stage_name" "docker exec '$CONTAINER_NAME' bash -c 'cd /workspace && cat /tmp/stage_prompt.txt | claude --dangerously-skip-permissions'"
    local stage_exit_code=$?
    local claude_end_time=$(date +%s)
    local claude_duration=$((claude_end_time - claude_start_time))
    
    if [ $stage_exit_code -ne 0 ]; then
        log_with_timestamp "⚠️  WARNING: Stage $stage_name failed with exit code $stage_exit_code"
        update_workflow_status "STAGE_ERROR" "$stage_name" "Exit code: $stage_exit_code"
    else
        log_with_timestamp "✅ Stage $stage_name completed successfully in ${claude_duration}s"
    fi
    
    # Generate handoff summary (separate Claude call)
    log_with_timestamp "📋 GENERATING HANDOFF SUMMARY..."
    update_workflow_status "GENERATING_HANDOFF" "$stage_name" "Creating handoff summary"
    
    local handoff_prompt=$(generate_handoff_prompt "$stage_name" "$stage_num")
    docker exec "$CONTAINER_NAME" bash -c "cat > /tmp/handoff_prompt.txt << 'EOF'
$handoff_prompt
EOF"
    
    # Capture handoff summary with retry mechanism
    local handoff_file="$HOST_HANDOFF_DIR/stage_${stage_num}_handoff.txt"
    local handoff_start_time=$(date +%s)
    log_with_timestamp "🔄 Requesting handoff summary from Claude..."
    retry_claude_operation "Claude handoff generation for $stage_name" "docker exec '$CONTAINER_NAME' bash -c 'cd /workspace && cat /tmp/handoff_prompt.txt | claude --dangerously-skip-permissions' > '$handoff_file'"
    local handoff_end_time=$(date +%s)
    local handoff_duration=$((handoff_end_time - handoff_start_time))
    
    # Check handoff quality
    local handoff_words=$(wc -w < "$handoff_file" 2>/dev/null || echo "0")
    log_with_timestamp "📊 Handoff summary: $handoff_words words, generated in ${handoff_duration}s"
    log_with_timestamp "💾 Handoff saved to: $handoff_file"
    
    # Clean up temp files
    docker exec "$CONTAINER_NAME" rm -f "/tmp/stage_prompt.txt" "/tmp/handoff_prompt.txt"
    
    # Calculate total stage time
    local stage_end_time=$(date +%s)
    local total_stage_duration=$((stage_end_time - stage_start_time))
    
    log_with_timestamp "🏁 Stage $stage_name COMPLETE - Total time: ${total_stage_duration}s"
    update_workflow_status "STAGE_COMPLETED" "$stage_name" "Completed in ${total_stage_duration}s"
    
    # Create stage summary file
    local stage_summary_file="$HOST_HANDOFF_DIR/stage_${stage_num}_summary.txt"
    cat > "$stage_summary_file" << EOF
STAGE SUMMARY: $stage_name (Stage $stage_num/$total_stages)
========================================================
Start Time: $(date -r $stage_start_time)
End Time: $(date -r $stage_end_time)
Duration: ${total_stage_duration}s
Claude Execution: ${claude_duration}s
Handoff Generation: ${handoff_duration}s
Exit Code: $stage_exit_code
Prompt Length: $prompt_length words
Context Length: $context_length words
Handoff Length: $handoff_words words
Status: $([ $stage_exit_code -eq 0 ] && echo "SUCCESS" || echo "ERROR")
Files Created:
- $prompt_file
- $handoff_file
- $stage_summary_file
EOF
    
    log_with_timestamp "📋 Stage summary saved to: $stage_summary_file"
    log_with_timestamp ""
    
    sleep 2
}

# Save initial task
log_with_timestamp "💾 Saving initial task to: $HOST_HANDOFF_DIR/initial_task.txt"
echo "$INITIAL_TASK" > "$HOST_HANDOFF_DIR/initial_task.txt"
task_words=$(echo "$INITIAL_TASK" | wc -w)
log_with_timestamp "📝 Initial task: $task_words words"

# Container setup with unique naming for multi-project support
PROJECT_NAME=$(basename "$REPO_DIR")
UNIQUE_ID="$(date +%s)_$(hostname)_$$"
CONTAINER_NAME="claude_handoff_${PROJECT_NAME}_${UNIQUE_ID}"
log_with_timestamp "🐳 Container name: $CONTAINER_NAME"

cleanup() {
    log_with_timestamp "🧹 Cleaning up container and finalizing logs..."
    update_workflow_status "CLEANUP" "" "Removing container and finalizing"
    docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1 || true
    
    # Create final workflow summary
    local workflow_end_time=$(date)
    cat >> "$HOST_HANDOFF_DIR/workflow_final_summary.txt" << EOF
WORKFLOW COMPLETED: $workflow_end_time
==========================================
Session ID: $SESSION_ID
Project: $REPO_DIR
Total Stages: ${#STAGES[@]}
Container: $CONTAINER_NAME
Handoff Directory: $HOST_HANDOFF_DIR

All files in handoff directory:
$(ls -la "$HOST_HANDOFF_DIR" 2>/dev/null | grep -v "^total")
EOF
    log_with_timestamp "📋 Final workflow summary saved to: $HOST_HANDOFF_DIR/workflow_final_summary.txt"
}

trap cleanup EXIT

log_with_timestamp "🐳 Starting Claude Code container..."
update_workflow_status "CONTAINER_STARTING" "" "Starting Docker container"

docker run -d --name "$CONTAINER_NAME" \
    --mount type=bind,source="$REPO_DIR",target=/workspace \
    --mount type=bind,source="$HOME/.claude",target=/home/dev/.claude \
    --user 1000:1000 --workdir /workspace \
    --env CLAUDE_CONFIG_DIR=/home/dev/.claude \
    --env CLAUDE_CODE_BYPASS_ALL_PERMISSIONS=1 \
    --env CLAUDE_CODE_SUPPRESS_UI_PROMPTS=1 \
    claude_code_container tail -f /dev/null > /dev/null 2>&1

sleep 2
log_with_timestamp "✅ Container started successfully"
update_workflow_status "CONTAINER_READY" "" "Container ready for stages"

# Execute all stages
log_with_timestamp "🚀 STARTING WORKFLOW EXECUTION"
log_with_timestamp "Total stages to execute: ${#STAGES[@]}"
log_with_timestamp "Stages: ${STAGES[*]}"

TOTAL_STAGES=${#STAGES[@]}
WORKFLOW_START_TIME=$(date +%s)
update_workflow_status "WORKFLOW_EXECUTING" "" "Executing ${TOTAL_STAGES} stages"

for i in "${!STAGES[@]}"; do
    STAGE="${STAGES[$i]}"
    STAGE_NUM=$((i + 1))
    
    log_with_timestamp ""
    log_with_timestamp "⏭️  Proceeding to stage $STAGE_NUM of $TOTAL_STAGES: $STAGE"
    execute_stage_with_handoff "$STAGE" "$STAGE_NUM" "$TOTAL_STAGES"
    
    # Show progress
    progress_percent=$(( (STAGE_NUM * 100) / TOTAL_STAGES ))
    log_with_timestamp "📊 Progress: $STAGE_NUM/$TOTAL_STAGES stages complete ($progress_percent%)"
done

# Final workflow completion
WORKFLOW_END_TIME=$(date +%s)
TOTAL_WORKFLOW_DURATION=$((WORKFLOW_END_TIME - WORKFLOW_START_TIME))
WORKFLOW_DURATION_MINUTES=$((TOTAL_WORKFLOW_DURATION / 60))
WORKFLOW_DURATION_SECONDS=$((TOTAL_WORKFLOW_DURATION % 60))

log_with_timestamp "🎉 =================================="
log_with_timestamp "🎉 HANDOFF WORKFLOW COMPLETE!"
log_with_timestamp "🎉 =================================="
log_with_timestamp "📊 Total execution time: ${WORKFLOW_DURATION_MINUTES}m ${WORKFLOW_DURATION_SECONDS}s"
log_with_timestamp "📁 All handoff summaries saved in: $HOST_HANDOFF_DIR"
log_with_timestamp "🆔 Session ID: $SESSION_ID"
log_with_timestamp "📋 Check workflow_status.txt for current status"
log_with_timestamp "📜 Check workflow_log.txt for detailed logs"

update_workflow_status "WORKFLOW_COMPLETED" "" "All ${TOTAL_STAGES} stages completed in ${WORKFLOW_DURATION_MINUTES}m ${WORKFLOW_DURATION_SECONDS}s"

# List all generated files for easy reference
log_with_timestamp ""
log_with_timestamp "📂 FILES GENERATED:"
ls -la "$HOST_HANDOFF_DIR" | while read line; do
    if [[ "$line" != "total "* ]]; then
        log_with_timestamp "   $line"
    fi
done