#!/bin/bash

# Claude Code Sequential Workflow with Context Handoffs
# Each stage runs as a separate conversation with structured summaries passed between

set -e

REPO_DIR="$1"
INITIAL_TASK="${2:-}"
SESSION_ID=$(uuidgen 2>/dev/null || echo "session-$$-$(date +%s)")
HANDOFF_DIR="/workspace/plan/handoffs"
STATUS_FILE="$HANDOFF_DIR/workflow_status.txt"
LOG_FILE="$HANDOFF_DIR/workflow_log.txt"

# Logging function with timestamps
log_with_timestamp() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" | tee -a "$LOG_FILE"
}

# Create fresh handoff directory (cleanup previous runs)
if [ -d "$HANDOFF_DIR" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🧹 Cleaning up previous handoff directory..."
    rm -rf "$HANDOFF_DIR"/*
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Previous handoffs cleared"
fi
mkdir -p "$HANDOFF_DIR"

# Initialize tracking files
echo "Workflow started at $(date)" > "$LOG_FILE"
echo "WORKFLOW_STATUS=INITIALIZING" > "$STATUS_FILE"
log_with_timestamp "📁 Fresh handoff directory created: $HANDOFF_DIR"

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

log_with_timestamp "=================================="
log_with_timestamp "Claude Code Handoff Workflow STARTED"
log_with_timestamp "=================================="
log_with_timestamp "Project: $REPO_DIR"
log_with_timestamp "Session ID: $SESSION_ID"
log_with_timestamp "Handoff Dir: $HANDOFF_DIR"
log_with_timestamp "Status File: $STATUS_FILE"
log_with_timestamp "Log File: $LOG_FILE"
log_with_timestamp ""

update_workflow_status "STARTING" "" "Initializing workflow components"

STAGES=(
    "investigate"
    "plan"
    "execute"
    "verify"
    "cleanup"
    "summary"
)

# Structured handoff prompt - captures essential context
generate_handoff_prompt() {
    local stage_name="$1"
    echo "/plan Save all information from this chat into your markdown plan file(s), then generate a detailed handoff summary.
    
Include:

## Current Stage: $stage_name

## Essential Context
- All information and principles from the original task specified by the user
- All information from this chat
- All project files created, modified, or deleted
- All plan/markdown files created, modified, or deleted
- Critical decisions made
- Any blockers or issues encountered
- Don't overcomplicate the handoff summary.

## Current State
- Information about all relevant files and directories
- Current status of the main task/objective
- Any intermediate results or findings

## For Next Stage
- What the next stage should focus on
- Any specific requirements or constraints
- Files/directories they should examine first
- If there is nothing left to do, just say so. Don't make up anything for the sake of it.

## Handoff Data
- Keep this summary under 1000 words
- Focus on actionable information
- Include specific file paths and concrete results
- Omit detailed explanations (focus on facts and next steps)

Output this handoff summary in plain text (not markdown) for easy parsing."
}

# Build context prompt from previous handoffs
build_context_from_handoffs() {
    local current_stage_num="$1"
    local context=""
    
    # Add initial task context
    if [ -f "$HANDOFF_DIR/initial_task.txt" ]; then
        context="## Original Task
$(cat "$HANDOFF_DIR/initial_task.txt")

"
    fi
    
    # Add summaries from all previous stages
    for ((i=1; i<current_stage_num; i++)); do
        local handoff_file="$HANDOFF_DIR/stage_${i}_handoff.txt"
        if [ -f "$handoff_file" ]; then
            context="${context}## Previous Stage $i Summary
$(cat "$handoff_file")

"
        fi
    done
    
    echo "$context"
}

# Common prompt fragments to avoid repetition
DEBUG_HELP="dont hesitate to use standalone/debugging scripts & add print lines during this task if helpful."
UPDATE_DOCS="update your planning/markdown file(s)."
USE_AGENTS="use many agents."
PLAN_SUFFIX="$DEBUG_HELP $UPDATE_DOCS $USE_AGENTS"

# Get stage-specific prompt
get_stage_prompt() {
    local stage_name="$1"
    case "$stage_name" in
        "investigate") echo "/plan conduct deep and thorough investigations, research, testing, debugging, etc on the task at hand. do not plan/execute yet, just investigate/research. $PLAN_SUFFIX" ;;
        "plan") echo "/plan create / continue to flesh out the plan. ensure that there is defined scope, no ambiguity, and no chance for overly complex solutions or overengineering. do not execute yet, just plan. $PLAN_SUFFIX" ;;
        "compact") echo "/compact remember everything so far in verbose detail. list the names/locations of all planning/markdown file(s) relevant in this conversation specifically." ;;
        "execute") echo "/plan execute the plan. if there is nothing left to do (within the plan and scope), then just return (do nothing). if there are remaining items, lets keep going. $PLAN_SUFFIX" ;;
        "verify") echo "/plan verify that all tasks in the plan are complete, through whatever means and methods required to verify and validate. $PLAN_SUFFIX" ;;
        "cleanup") echo "/plan conduct a deep and thorough cleanup of the project. remove all files and directories that are no longer needed." ;;
        "summary") echo "/plan summarize this conversation so far. output the summary here (not into a file)." ;;
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
    local stage_prompt=$(get_stage_prompt "$stage_name")
    
    # Create full prompt with SLASH COMMAND FIRST, then context
    local full_prompt="$stage_prompt

## Context from Previous Stages
$context"
    
    local prompt_length=$(echo "$full_prompt" | wc -w)
    log_with_timestamp "📄 Full prompt created: $prompt_length total words"
    
    # Save prompt to file for debugging
    local prompt_file="$HANDOFF_DIR/stage_${stage_num}_prompt.txt"
    echo "$full_prompt" > "$prompt_file"
    log_with_timestamp "💾 Prompt saved to: $prompt_file"
    
    log_with_timestamp "🚀 EXECUTING STAGE $stage_name..."
    update_workflow_status "STAGE_EXECUTING" "$stage_name" "Claude processing stage $stage_num"
    
    # Execute stage (NEW conversation each time - no -c flag)
    log_with_timestamp "📤 Sending prompt to Claude container..."
    docker exec "$CONTAINER_NAME" bash -c "cat > /tmp/stage_prompt.txt << 'EOF'
$full_prompt
EOF"
    
    # Run the stage
    log_with_timestamp "⚡ Claude is processing stage $stage_name..."
    local claude_start_time=$(date +%s)
    docker exec "$CONTAINER_NAME" bash -c "cd /workspace && cat /tmp/stage_prompt.txt | claude --dangerously-skip-permissions"
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
    
    local handoff_prompt=$(generate_handoff_prompt "$stage_name")
    docker exec "$CONTAINER_NAME" bash -c "cat > /tmp/handoff_prompt.txt << 'EOF'
$handoff_prompt
EOF"
    
    # Capture handoff summary
    local handoff_file="$HANDOFF_DIR/stage_${stage_num}_handoff.txt"
    local handoff_start_time=$(date +%s)
    log_with_timestamp "🔄 Requesting handoff summary from Claude..."
    docker exec "$CONTAINER_NAME" bash -c "cd /workspace && cat /tmp/handoff_prompt.txt | claude --dangerously-skip-permissions" > "$handoff_file"
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
    local stage_summary_file="$HANDOFF_DIR/stage_${stage_num}_summary.txt"
    cat > "$stage_summary_file" << EOF
STAGE SUMMARY: $stage_name (Stage $stage_num/$total_stages)
========================================================
Start Time: $(date -d @$stage_start_time)
End Time: $(date -d @$stage_end_time)
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
log_with_timestamp "💾 Saving initial task to: $HANDOFF_DIR/initial_task.txt"
echo "$INITIAL_TASK" > "$HANDOFF_DIR/initial_task.txt"
task_words=$(echo "$INITIAL_TASK" | wc -w)
log_with_timestamp "📝 Initial task: $task_words words"

# Container setup
CONTAINER_NAME="claude_handoff_$(basename "$REPO_DIR")_$$"
log_with_timestamp "🐳 Container name: $CONTAINER_NAME"

cleanup() {
    log_with_timestamp "🧹 Cleaning up container and finalizing logs..."
    update_workflow_status "CLEANUP" "" "Removing container and finalizing"
    docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1 || true
    
    # Create final workflow summary
    local workflow_end_time=$(date)
    cat >> "$HANDOFF_DIR/workflow_final_summary.txt" << EOF
WORKFLOW COMPLETED: $workflow_end_time
==========================================
Session ID: $SESSION_ID
Project: $REPO_DIR
Total Stages: ${#STAGES[@]}
Container: $CONTAINER_NAME
Handoff Directory: $HANDOFF_DIR

All files in handoff directory:
$(ls -la "$HANDOFF_DIR" 2>/dev/null | grep -v "^total")
EOF
    log_with_timestamp "📋 Final workflow summary saved to: $HANDOFF_DIR/workflow_final_summary.txt"
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
log_with_timestamp "📁 All handoff summaries saved in: $HANDOFF_DIR"
log_with_timestamp "🆔 Session ID: $SESSION_ID"
log_with_timestamp "📋 Check workflow_status.txt for current status"
log_with_timestamp "📜 Check workflow_log.txt for detailed logs"

update_workflow_status "WORKFLOW_COMPLETED" "" "All ${TOTAL_STAGES} stages completed in ${WORKFLOW_DURATION_MINUTES}m ${WORKFLOW_DURATION_SECONDS}s"

# List all generated files for easy reference
log_with_timestamp ""
log_with_timestamp "📂 FILES GENERATED:"
ls -la "$HANDOFF_DIR" | while read line; do
    if [[ "$line" != "total "* ]]; then
        log_with_timestamp "   $line"
    fi
done