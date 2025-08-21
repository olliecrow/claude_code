#!/bin/bash

# Claude Code Sequential Workflow with Context Handoffs
# Each stage runs as a separate conversation with structured summaries passed between

set -e

REPO_DIR="$1"
INITIAL_TASK="${2:-}"
SESSION_ID=$(uuidgen 2>/dev/null || echo "session-$$-$(date +%s)")
HANDOFF_DIR="/workspace/plan/handoffs"

# Create handoff directory
mkdir -p "$HANDOFF_DIR"

echo "=================================="
echo "Claude Code Handoff Workflow"
echo "=================================="
echo "Project: $REPO_DIR"
echo "Session ID: $SESSION_ID"
echo "Handoff Dir: $HANDOFF_DIR"

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
- All plan files created, modified, or deleted
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
    
    echo "=================================="
    echo "Stage $stage_num/$total_stages: $stage_name"
    echo "Session: $SESSION_ID"
    echo "=================================="
    
    # Build context from previous handoffs
    local context=$(build_context_from_handoffs "$stage_num")
    local stage_prompt=$(get_stage_prompt "$stage_name")
    
    # Create full prompt with SLASH COMMAND FIRST, then context
    local full_prompt="$stage_prompt

## Context from Previous Stages
$context"
    
    # Save prompt to file for debugging
    echo "$full_prompt" > "$HANDOFF_DIR/stage_${stage_num}_prompt.txt"
    
    echo "--- EXECUTING STAGE $stage_name ---"
    
    # Execute stage (NEW conversation each time - no -c flag)
    docker exec "$CONTAINER_NAME" bash -c "cat > /tmp/stage_prompt.txt << 'EOF'
$full_prompt
EOF"
    
    # Run the stage
    docker exec "$CONTAINER_NAME" bash -c "cd /workspace && cat /tmp/stage_prompt.txt | claude --dangerously-skip-permissions"
    local stage_exit_code=$?
    
    if [ $stage_exit_code -ne 0 ]; then
        echo "Warning: Stage $stage_name failed with code $stage_exit_code"
    fi
    
    # Generate handoff summary (separate Claude call)
    echo "--- GENERATING HANDOFF SUMMARY ---"
    
    local handoff_prompt=$(generate_handoff_prompt "$stage_name")
    docker exec "$CONTAINER_NAME" bash -c "cat > /tmp/handoff_prompt.txt << 'EOF'
$handoff_prompt
EOF"
    
    # Capture handoff summary
    docker exec "$CONTAINER_NAME" bash -c "cd /workspace && cat /tmp/handoff_prompt.txt | claude --dangerously-skip-permissions" > "$HANDOFF_DIR/stage_${stage_num}_handoff.txt"
    
    # Clean up temp files
    docker exec "$CONTAINER_NAME" rm -f "/tmp/stage_prompt.txt" "/tmp/handoff_prompt.txt"
    
    echo "Stage $stage_name completed. Handoff saved to: $HANDOFF_DIR/stage_${stage_num}_handoff.txt"
    echo ""
    
    sleep 2
}

# Save initial task
echo "$INITIAL_TASK" > "$HANDOFF_DIR/initial_task.txt"

# Container setup (same as original)
CONTAINER_NAME="claude_handoff_$(basename "$REPO_DIR")_$$"

cleanup() {
    echo "Cleaning up..."
    docker rm -f "$CONTAINER_NAME" > /dev/null 2>&1 || true
}

trap cleanup EXIT

docker run -d --name "$CONTAINER_NAME" \
    --mount type=bind,source="$REPO_DIR",target=/workspace \
    --mount type=bind,source="$HOME/.claude",target=/home/dev/.claude \
    --user 1000:1000 --workdir /workspace \
    --env CLAUDE_CONFIG_DIR=/home/dev/.claude \
    --env CLAUDE_CODE_BYPASS_ALL_PERMISSIONS=1 \
    --env CLAUDE_CODE_SUPPRESS_UI_PROMPTS=1 \
    claude_code_container tail -f /dev/null > /dev/null 2>&1

sleep 2

# Execute all stages
TOTAL_STAGES=${#STAGES[@]}
for i in "${!STAGES[@]}"; do
    STAGE="${STAGES[$i]}"
    STAGE_NUM=$((i + 1))
    
    execute_stage_with_handoff "$STAGE" "$STAGE_NUM" "$TOTAL_STAGES"
done

echo "=================================="
echo "Handoff Workflow Complete!"
echo "=================================="
echo "All handoff summaries saved in: $HANDOFF_DIR"
echo "Session ID: $SESSION_ID"