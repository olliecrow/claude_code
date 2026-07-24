#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=container/claude_common_lib.sh
source "$script_directory/claude_common_lib.sh"

usage() {
    cat <<EOF
Usage:
  $(basename "$0") /path/to/prompts.txt
  $(basename "$0") /path/to/project /path/to/prompts.txt

Blank lines separate prompts. Lines beginning with # are comments.
A prompt beginning with /compact starts a fresh conversation with a handoff.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

case "$#" in
    1)
        project_directory="$(pwd)"
        prompts_path="$1"
        ;;
    2)
        project_directory="$1"
        prompts_path="$2"
        ;;
    *)
        usage >&2
        exit 1
        ;;
esac

require_directory "$project_directory"

if [[ ! -f "$prompts_path" ]]; then
    echo "Error: prompts file does not exist: $prompts_path" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required to parse Claude's JSON output." >&2
    exit 1
fi

project_directory="$(absolute_directory "$project_directory")"
prompts_file="$(cd "$(dirname "$prompts_path")" && pwd -P)/$(basename "$prompts_path")"
host_timezone="$(detect_host_timezone)"
project_name="$(safe_container_component "$(basename "$project_directory")")"
container_name="claude_sequence_${project_name}_$(date +%s)_$$"
handoff_directory="$project_directory/plan/handoffs"
workflow_log="$handoff_directory/workflow_log.txt"
workflow_status="$handoff_directory/workflow_status.txt"
temporary_directory=""
container_started=0
workflow_complete=0
handoff_initialized=0

timestamp() {
    date '+%Y-%m-%dT%H:%M:%S%z'
}

log() {
    local message="$*"
    printf '[%s] %s\n' "$(timestamp)" "$message" | tee -a "$workflow_log"
}

write_status() {
    local status="$1"
    printf '%s %s\n' "$status" "$(timestamp)" > "$workflow_status"
}

cleanup() {
    local exit_code=$?

    if [[ "$container_started" -eq 1 ]]; then
        stop_container "$container_name"
    fi
    if [[ -n "$temporary_directory" ]]; then
        rm -rf -- "$temporary_directory"
    fi

    if [[ "$workflow_complete" -eq 0 && "$handoff_initialized" -eq 1 ]]; then
        write_status "FAILED" || true
        log "Workflow failed with status $exit_code." || true
    fi

    exit "$exit_code"
}

prompts=()
current_prompt=""
while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"

    if [[ "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi

    if [[ -z "${line//[[:space:]]/}" ]]; then
        if [[ -n "${current_prompt//[[:space:]]/}" ]]; then
            prompts+=("$current_prompt")
            current_prompt=""
        fi
        continue
    fi

    if [[ -n "$current_prompt" ]]; then
        current_prompt+=$'\n'
    fi
    current_prompt+="$line"
done < "$prompts_file"

if [[ -n "${current_prompt//[[:space:]]/}" ]]; then
    prompts+=("$current_prompt")
fi

if [[ "${#prompts[@]}" -eq 0 ]]; then
    echo "Error: the prompts file contains no prompts." >&2
    exit 1
fi

require_claude_auth
require_docker

temporary_directory="$(mktemp -d)"
trap cleanup EXIT
mkdir -p "$handoff_directory"
: > "$workflow_log"
handoff_initialized=1

extract_json_field() {
    local source_file="$1"
    local field_name="$2"
    local destination_file="$3"

    python3 - "$source_file" "$field_name" "$destination_file" <<'PY'
import json
import sys
from pathlib import Path

source = Path(sys.argv[1])
field = sys.argv[2]
destination = Path(sys.argv[3])

try:
    data = json.loads(source.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as error:
    raise SystemExit(f"Could not parse Claude JSON output: {error}")

value = data.get(field)
if not isinstance(value, str):
    raise SystemExit(f"Claude JSON output did not contain a string field named {field!r}")

destination.write_text(value, encoding="utf-8")
PY
}

run_claude_turn() {
    local prompt_text="$1"
    local session_id="$2"
    local json_output="$3"
    local claude_arguments=(
        -p
        --model sonnet
        --dangerously-skip-permissions
        --output-format json
    )

    if [[ -n "$session_id" ]]; then
        claude_arguments+=(--resume "$session_id")
    fi

    printf '%s\n' "$prompt_text" | docker exec -i -w /workspace "$container_name" \
        claude "${claude_arguments[@]}" > "$json_output"
}

append_response() {
    local transcript_file="$1"
    local response_number="$2"
    local response_file="$3"

    {
        printf '## Response %s\n\n' "$response_number"
        cat "$response_file"
        printf '\n\n'
    } >> "$transcript_file"
}

handoff_prompt() {
    cat <<'EOF'
Create a concise handoff for a fresh conversation. Include the original goal,
work completed, files changed, decisions and constraints, verification evidence,
remaining work, and any blocker. Preserve exact paths or commands only when they
are needed to continue. Output only the handoff.
EOF
}

previous_handoff=""
initial_task_written=0
conversation_count=0

run_conversation() {
    local conversation_number="$1"
    shift
    local conversation_prompts=("$@")
    local transcript_file="$handoff_directory/conversation_${conversation_number}.txt"
    local handoff_file="$handoff_directory/conversation_${conversation_number}_handoff.txt"
    local session_file="$temporary_directory/session_${conversation_number}.txt"
    local json_file=""
    local result_file=""
    local session_id=""
    local prompt_text=""
    local full_prompt=""
    local response_number=1

    : > "$transcript_file"

    if [[ "$initial_task_written" -eq 0 ]]; then
        printf '%s\n' "${conversation_prompts[0]}" > "$handoff_directory/initial_task.txt"
        initial_task_written=1
    fi

    log "Conversation $conversation_number: running ${#conversation_prompts[@]} prompt(s)."

    for prompt_text in "${conversation_prompts[@]}"; do
        full_prompt="$prompt_text"
        if [[ "$response_number" -eq 1 && -n "$previous_handoff" ]]; then
            full_prompt="Previous conversation handoff:
$previous_handoff

Current task:
$prompt_text"
        fi

        json_file="$temporary_directory/conversation_${conversation_number}_${response_number}.json"
        result_file="$temporary_directory/conversation_${conversation_number}_${response_number}.txt"
        run_claude_turn "$full_prompt" "$session_id" "$json_file"

        if [[ -z "$session_id" ]]; then
            extract_json_field "$json_file" "session_id" "$session_file"
            session_id="$(< "$session_file")"
        fi

        extract_json_field "$json_file" "result" "$result_file"
        append_response "$transcript_file" "$response_number" "$result_file"
        response_number=$((response_number + 1))
    done

    json_file="$temporary_directory/conversation_${conversation_number}_handoff.json"
    run_claude_turn "$(handoff_prompt)" "$session_id" "$json_file"
    extract_json_field "$json_file" "result" "$handoff_file"
    previous_handoff="$(< "$handoff_file")"
    conversation_count=$((conversation_count + 1))
    log "Conversation $conversation_number: handoff saved."
}

print_trust_warning
echo "Project: $project_directory"
echo "Prompts: $prompts_file"
echo "Handoffs: $handoff_directory"
write_status "STARTED"

start_claude_container "$container_name" "$project_directory" "$host_timezone" >/dev/null
container_started=1
log "Container started."

conversation_number=1
conversation_prompts=()

for prompt_text in "${prompts[@]}"; do
    if [[ "$prompt_text" == "/compact" || "$prompt_text" == "/compact "* || "$prompt_text" == $'/compact\n'* ]]; then
        if [[ "${#conversation_prompts[@]}" -gt 0 ]]; then
            run_conversation "$conversation_number" "${conversation_prompts[@]}"
            conversation_prompts=()
            conversation_number=$((conversation_number + 1))
        fi

        remaining_prompt="${prompt_text:8}"
        remaining_prompt="${remaining_prompt#"${remaining_prompt%%[![:space:]]*}"}"
        if [[ -n "$remaining_prompt" ]]; then
            conversation_prompts+=("$remaining_prompt")
        fi
    else
        conversation_prompts+=("$prompt_text")
    fi
done

if [[ "${#conversation_prompts[@]}" -gt 0 ]]; then
    run_conversation "$conversation_number" "${conversation_prompts[@]}"
fi

if [[ "$conversation_count" -eq 0 ]]; then
    echo "Error: no executable prompts remained after /compact directives." >&2
    exit 1
fi

workflow_complete=1
write_status "COMPLETED"
log "Workflow completed: $conversation_count conversation(s)."
