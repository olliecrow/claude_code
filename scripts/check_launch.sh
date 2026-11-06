#!/usr/bin/env bash
# Mock Docker checks for auth forwarding and failed container startup.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
library="$repository_root/container/claude_common_lib.sh"

unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY CLAUDE_CONTAINER_MOUNT_HOST_CONFIG || true

scratch="$(mktemp -d)"
cleanup() {
    chmod -R u+rwX -- "$scratch"
    rm -rf -- "$scratch"
}
trap cleanup EXIT

fail() {
    echo "launch check failed: $1" >&2
    exit 1
}

mode_of() {
    python3 -c 'import os, sys; print(format(os.stat(sys.argv[1]).st_mode & 0o777, "03o"))' "$1"
}

set_run_dir() {
    local case_dir="$1"
    local found=()
    shopt -s nullglob
    found=("$case_dir"/xdg/claude_code/runs/run.*)
    shopt -u nullglob
    [[ "${#found[@]}" -eq 1 ]] || fail "expected one private run directory in ${case_dir}, found ${#found[@]}"
    run_dir="${found[0]}"
}

assert_private_handoffs() {
    local dir="$1"
    [[ "$(mode_of "$dir")" == 700 ]] || fail "run directory is not private"
    [[ "$(mode_of "$dir/handoffs")" == 700 ]] || fail "handoff directory is not private"
    [[ "$(mode_of "$(dirname -- "$dir")")" == 700 ]] || fail "run parent is not private"
    [[ -f "$dir/handoffs/conversation_1.txt" && ! -L "$dir/handoffs/conversation_1.txt" ]] ||
        fail "transcript was not kept"
    [[ -f "$dir/handoffs/conversation_1_handoff.txt" && ! -L "$dir/handoffs/conversation_1_handoff.txt" ]] ||
        fail "handoff was not kept"
    grep -F 'done' "$dir/handoffs/conversation_1.txt" >/dev/null || fail "transcript was not saved"
    grep -F 'COMPLETED' "$dir/handoffs/workflow_status.txt" >/dev/null || fail "status was not saved"
    [[ ! -e "$dir/home" && ! -e "$dir/work" && ! -e "$dir/container.id" ]] ||
        fail "container home was kept after removal"
}

container_id="$(printf 'ab%.0s' {1..32})"
[[ "${#container_id}" -eq 64 ]] || fail "container id fixture length"

project="$scratch/project"
mkdir -p "$project"
printf 'hello\n' > "$scratch/prompts.txt"

mock_bin="$scratch/bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
log="${DOCKER_MOCK_LOG:?}"
mode="${DOCKER_MOCK_MODE:?}"
state="${DOCKER_MOCK_STATE:?}"
case "$1" in
    info)
        count_file="$state/info-count"
        count=0
        if [[ -f "$count_file" ]]; then
            count="$(cat "$count_file")"
        fi
        count=$((count + 1))
        printf '%s\n' "$count" > "$count_file"
        if [[ "$mode" == daemon-down && "$count" -gt 2 ]]; then
            echo "Cannot connect to the Docker daemon" >&2
            exit 1
        fi
        if [[ "$mode" == rootless ]]; then
            printf '[name=rootless]\n'
        fi
        exit 0
        ;;
    image)
        exit 0
        ;;
    run)
        printf 'run\n' >> "$log"
        cidfile=""
        previous=""
        for argument in "$@"; do
            if [[ "$previous" == "--cidfile" ]]; then
                cidfile="$argument"
            fi
            previous="$argument"
        done
        if [[ "$mode" == bad-id ]]; then
            [[ -n "$cidfile" ]] || exit 2
            printf 'not-an-id\n' > "$cidfile"
            printf '%s\n' "$cidfile" > "$state/cidfile-path"
            printf 'created\n' >> "$log"
            exit 0
        fi
        if [[ "$mode" == "start-fail" || "$mode" == readonly || "$mode" == delete-fail || "$mode" == success || "$mode" == plant || "$mode" == directory || "$mode" == fifo || "$mode" == linked || "$mode" == rm-fail || "$mode" == daemon-down || "$mode" == absent || "$mode" == inspect-fail ]]; then
            [[ -n "$cidfile" ]] || exit 2
            printf '%s\n' "${DOCKER_MOCK_ID:?}" > "$cidfile"
            printf '%s\n' "$cidfile" > "$state/cidfile-path"
            printf 'created\n' >> "$log"
            [[ "$mode" == "start-fail" ]] || exit 0
            exit 125
        fi
        if [[ "$mode" == "create-fail" ]]; then
            printf 'create-failed\n' >> "$log"
            exit 125
        fi
        exit 2
        ;;
    exec)
        [[ "${5:-}" == "${DOCKER_MOCK_ID:?}" ]] || exit 3
        printf 'exec %s\n' "$5" >> "$log"
        if [[ "$mode" == plant ]]; then
            # Act like a container that points a handoff file at a host file.
            mkdir -p "${DOCKER_MOCK_PLANT_DIR:?}"
            ln -sfn "${DOCKER_MOCK_PLANT_TARGET:?}" "$DOCKER_MOCK_PLANT_DIR/conversation_1_handoff.txt"
        fi
        [[ "$2" != -i ]] || cat >/dev/null
        printf '{"result":"done","session_id":"test-session"}\n'
        exit 0
        ;;
    rm)
        id="${3:-}"
        if [[ ! "$id" =~ ^[0-9a-fA-F]{64}$ ]]; then
            printf 'removed-by-name %s\n' "$id" >> "$log"
            exit 2
        fi
        cidfile="$(cat "$state/cidfile-path")"
        if [[ -d "$(dirname "$cidfile")/home" ]]; then
            printf 'home-present\n' >> "$log"
        else
            printf 'home-missing\n' >> "$log"
        fi
        if [[ "$mode" == rm-fail || "$mode" == daemon-down || "$mode" == absent || "$mode" == inspect-fail ]]; then
            printf 'rm-failed %s\n' "$id" >> "$log"
            exit 1
        fi
        if [[ "$mode" == readonly ]]; then
            run_home="$(dirname "$cidfile")/home"
            mkdir -p "$run_home/sub/nested"
            printf 'cache\n' > "$run_home/sub/nested/cache"
            chmod 444 "$run_home/sub/nested/cache"
            chmod 555 "$run_home/sub/nested" "$run_home/sub"
            ln -s "${DOCKER_MOCK_SENTINEL:?}" "$run_home/outside"
        fi
        printf 'removed %s\n' "$id" >> "$log"
        exit 0
        ;;
    container)
        if [[ "${2:-}" == inspect ]]; then
            printf 'inspect %s\n' "${3:-}" >> "$log"
            if [[ "$mode" == rm-fail ]]; then
                exit 0
            fi
            if [[ "$mode" == inspect-fail ]]; then
                echo "Error: service unavailable" >&2
                exit 1
            fi
            echo "Error: No such container: ${3:-}" >&2
            exit 1
        fi
        printf 'unexpected %s\n' "$1" >> "$log"
        exit 2
        ;;
    *)
        printf 'unexpected %s\n' "$1" >> "$log"
        exit 2
        ;;
esac
EOF
chmod 755 "$mock_bin/docker"
# The launchers must never run host Git. The container can plant Git metadata
# (a submodule .git file, or a new .git) that host Git would trust.
cat > "$mock_bin/git" <<'EOF'
#!/usr/bin/env bash
printf 'host-git %s\n' "$*" >> "${DOCKER_MOCK_LOG:?}"
exit 1
EOF
chmod 755 "$mock_bin/git"

# Fail only the verified run-home deletion; allow test teardown to use real rm.
real_rm="$(command -v rm)"
cat > "$mock_bin/rm" <<'EOF'
#!/usr/bin/env bash
if [[ "${DOCKER_MOCK_MODE:-}" == delete-fail ]]; then
    cidfile="$(cat "${DOCKER_MOCK_STATE:?}/cidfile-path")"
    if [[ "${!#}" == "$(dirname "$cidfile")/home" ]]; then
        exit 1
    fi
fi
exec "${DOCKER_MOCK_REAL_RM:?}" "$@"
EOF
chmod 755 "$mock_bin/rm"
export DOCKER_MOCK_REAL_RM="$real_rm"

assert_args_have() {
    local args_file="$1"
    local expected="$2"
    if ! grep -Fx -- "$expected" "$args_file" >/dev/null; then
        fail "missing docker argument ${expected}"
    fi
}

assert_args_lack() {
    local args_file="$1"
    local unexpected="$2"
    if grep -F -- "$unexpected" "$args_file" >/dev/null; then
        fail "unexpected docker argument ${unexpected}"
    fi
}

record_docker_args() {
    local args_file="$1"
    shift
    # shellcheck disable=SC2317
    docker() {
        printf '%s\n' "$@" > "$args_file"
    }
    # shellcheck source=container/claude_common_lib.sh
    source "$library"
    start_claude_container "$@"
}

oauth_args="$scratch/oauth-args.txt"
(
    export CLAUDE_CODE_OAUTH_TOKEN=dummyoauth
    # shellcheck disable=SC2030
    export ANTHROPIC_API_KEY=dummyapikey
    record_docker_args "$oauth_args" "name" "$project" "" "$scratch/mount" "$scratch/oauth.id"
)
assert_args_have "$oauth_args" "CLAUDE_CODE_OAUTH_TOKEN"
assert_args_have "$oauth_args" "--cidfile"
assert_args_lack "$oauth_args" "ANTHROPIC_API_KEY"

# Existing Git directories and worktree files must be masked read-only.
for git_kind in directory file absent; do
    git_project="$scratch/git-$git_kind"
    mkdir "$git_project"
    case "$git_kind" in
        directory) mkdir "$git_project/.git" ;;
        file) printf 'gitdir: ../external-metadata\n' > "$git_project/.git" ;;
    esac
    git_args="$scratch/git-$git_kind.txt"
    (record_docker_args "$git_args" name "$git_project" "" "$scratch/mount")
    mount="type=bind,source=$git_project/.git,target=/workspace/.git,readonly"
    if [[ "$git_kind" == absent ]]; then
        assert_args_lack "$git_args" "$mount"
    else
        assert_args_have "$git_args" "$mount"
        project_line="$(grep -nFx "type=bind,source=$git_project,target=/workspace" "$git_args" | cut -d: -f1)"
        git_line="$(grep -nFx "$mount" "$git_args" | cut -d: -f1)"
        [[ "$git_line" -gt "$project_line" ]] || fail "Git mask precedes project mount"
    fi
done

api_args="$scratch/api-args.txt"
(
    # shellcheck disable=SC2031
    export ANTHROPIC_API_KEY=dummyapikey
    record_docker_args "$api_args" "name" "$project" "" "$scratch/mount" "$scratch/api.id"
)
assert_args_have "$api_args" "ANTHROPIC_API_KEY"
assert_args_lack "$api_args" "CLAUDE_CODE_OAUTH_TOKEN"

file_args="$scratch/file-args.txt"
file_home="$scratch/credentials-home"
mkdir -p "$file_home/.claude"
printf '{}\n' > "$file_home/.claude/.credentials.json"
(
    export HOME="$file_home"
    record_docker_args "$file_args" "name" "$project" "" "$scratch/mount" "$scratch/file.id"
)
assert_args_lack "$file_args" "CLAUDE_CODE_OAUTH_TOKEN"
assert_args_lack "$file_args" "ANTHROPIC_API_KEY"
assert_args_have "$file_args" "--cidfile"

dry_output="$scratch/dry.txt"
mkdir -p "$scratch/dry-home"
if ! env \
    HOME="$scratch/dry-home" \
    CLAUDE_CODE_OAUTH_TOKEN=dummyoauth \
    ANTHROPIC_API_KEY=dummyapikey \
    bash "$repository_root/container/dry_run.sh" "$project" > "$dry_output"; then
    fail "dry run exited non-zero"
fi
if ! grep -Fx 'Forwards only CLAUDE_CODE_OAUTH_TOKEN.' "$dry_output" >/dev/null; then
    fail "dry run did not name the single forwarded variable"
fi
if grep -F 'ANTHROPIC_API_KEY' "$dry_output" >/dev/null; then
    fail "dry run mentioned the unused auth variable"
fi

# Give the interactive launcher a terminal without using a live Docker daemon.
cat > "$scratch/terminal.py" <<'PYTHON'
import os
import pty
import sys
sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))
PYTHON

run_launcher() {
    local mode="$1"
    local script_name="$2"
    shift 2
    local case_dir="$scratch/case-${mode}-${script_name}"
    local log="$case_dir/docker.log"
    local state="$case_dir/state"
    local temp_root="$case_dir/tmp"
    local fake_home="$case_dir/home"
    mkdir -p "$state" "$temp_root" "$fake_home"
    local status=0
    local command=(bash "$repository_root/container/$script_name")
    if [[ "$script_name" == run.sh ]]; then
        command=(python3 "$scratch/terminal.py" "${command[@]}")
    fi
    if [[ -n "${LAUNCH_TIMEOUT:-}" ]]; then
        command=(timeout "$LAUNCH_TIMEOUT" "${command[@]}")
    fi
    local state_home="${LAUNCH_STATE_HOME:-$case_dir/xdg}"
    (
        cd -- "$fake_home"
        env \
            HOME="$fake_home" \
            TMPDIR="$temp_root" \
            XDG_STATE_HOME="$state_home" \
            PATH="$mock_bin:$PATH" \
            CLAUDE_CODE_OAUTH_TOKEN=dummyoauth \
            DOCKER_MOCK_LOG="$log" \
            DOCKER_MOCK_MODE="$mode" \
            DOCKER_MOCK_ID="$container_id" \
            DOCKER_MOCK_STATE="$state" \
            "${command[@]}" "$@" \
            > "$case_dir/stdout" 2> "$case_dir/stderr"
    ) || status=$?
    printf '%s\n' "$status"
    if grep -F 'host-git' "$log" >/dev/null 2>&1; then
        fail "${script_name} ${mode} ran host Git"
    fi
    if [[ -n "$(find "$temp_root" -mindepth 1 -print -quit)" ]]; then
        fail "${script_name} ${mode} left a temporary directory"
    fi
}

expect_start_failure_cleaned() {
    local script_name="$1"
    shift
    local status
    status="$(run_launcher start-fail "$script_name" "$@")"
    [[ "$status" -eq 125 ]] || fail "${script_name} start failure exited ${status}"
    local log="$scratch/case-start-fail-${script_name}/docker.log"
    grep -Fx 'created' "$log" >/dev/null || fail "${script_name} did not record creation"
    grep -Fx "removed ${container_id}" "$log" >/dev/null || fail "${script_name} did not remove the created id"
    grep -Fx 'home-present' "$log" >/dev/null || fail "${script_name} removed the home before the container"
}

expect_create_failure_keeps_other_containers() {
    local script_name="$1"
    shift
    local status
    status="$(run_launcher create-fail "$script_name" "$@")"
    [[ "$status" -eq 125 ]] || fail "${script_name} create failure exited ${status}"
    local log="$scratch/case-create-fail-${script_name}/docker.log"
    grep -Fx 'create-failed' "$log" >/dev/null || fail "${script_name} did not record the create failure"
    if grep -F 'removed' "$log" >/dev/null; then
        fail "${script_name} removed a container it did not create"
    fi
}

expect_start_failure_cleaned run_sequence_prompts.sh "$project" "$scratch/prompts.txt"
expect_create_failure_keeps_other_containers run_sequence_prompts.sh "$project" "$scratch/prompts.txt"
expect_start_failure_cleaned run_command.sh "$project" "hello"
expect_create_failure_keeps_other_containers run_command.sh "$project" "hello"

expect_start_failure_cleaned run.sh "$project"
expect_create_failure_keeps_other_containers run.sh "$project"

for launcher in run.sh run_command.sh run_sequence_prompts.sh; do
    arguments=("$project" hello)
    [[ "$launcher" != run.sh ]] || arguments=("$project")
    [[ "$launcher" != run_sequence_prompts.sh ]] || arguments=("$project" "$scratch/prompts.txt")
    rootless_status="$(run_launcher rootless "$launcher" "${arguments[@]}")"
    [[ "$rootless_status" -eq 1 ]] || fail "$launcher did not reject rootless Docker"
    grep -F 'rootless Docker maps the container user to another uid; use rootful Docker.' \
        "$scratch/case-rootless-$launcher/stderr" "$scratch/case-rootless-$launcher/stdout" >/dev/null || fail "missing rootless message"
    success_status="$(run_launcher success "$launcher" "${arguments[@]}")"
    [[ "$success_status" -eq 0 ]] || fail "$launcher did not exec recorded ID"
    grep -Fx "exec $container_id" "$scratch/case-success-$launcher/docker.log" >/dev/null || fail "exec was not called"
done

[[ ! -e "$project/plan" ]] || fail "sequence wrote into the project"
set_run_dir "$scratch/case-success-run_sequence_prompts.sh"
assert_private_handoffs "$run_dir"
grep -F "Handoffs: $run_dir/handoffs" \
    "$scratch/case-success-run_sequence_prompts.sh/stdout" >/dev/null ||
    fail "handoff path was not printed"
for plain_launcher in run.sh run_command.sh; do
    if [[ -n "$(find "$scratch/case-success-$plain_launcher/xdg" -type d -name 'run.*' -print -quit)" ]]; then
        fail "$plain_launcher kept an empty run directory"
    fi
done

# The host must not follow links or directories the container plants in the
# project. Handoffs stay in the private directory.
plant_project="$scratch/plant-project"
plant_handoffs="$plant_project/plan/handoffs"
mkdir -p "$plant_handoffs"
for host_file in transcript log secret; do
    printf 'keep\n' > "$scratch/host-$host_file"
done
ln -s "$scratch/host-transcript" "$plant_handoffs/conversation_1.txt"
ln -s "$scratch/host-log" "$plant_handoffs/workflow_log.txt"
mkfifo "$plant_handoffs/workflow_status.txt"
plant_status="$(
    export DOCKER_MOCK_PLANT_DIR="$plant_handoffs" DOCKER_MOCK_PLANT_TARGET="$scratch/host-secret"
    run_launcher plant run_sequence_prompts.sh "$plant_project" "$scratch/prompts.txt"
)"
[[ "$plant_status" -eq 0 ]] || fail "planted links run exited $plant_status"
for host_file in transcript log secret; do
    [[ "$(cat "$scratch/host-$host_file")" == keep ]] || fail "host followed a planted link to host-$host_file"
done
[[ -L "$plant_handoffs/conversation_1.txt" && -L "$plant_handoffs/workflow_log.txt" ]] ||
    fail "planted links were replaced in the project"
[[ -p "$plant_handoffs/workflow_status.txt" ]] || fail "planted fifo was replaced in the project"
set_run_dir "$scratch/case-plant-run_sequence_prompts.sh"
assert_private_handoffs "$run_dir"

directory_project="$scratch/directory-project"
mkdir -p "$directory_project/plan/handoffs/conversation_1.txt"
printf 'keep\n' > "$scratch/directory-sentinel"
ln -s "$scratch/directory-sentinel" \
    "$directory_project/plan/handoffs/conversation_1.txt/conversation_1.txt"
directory_status="$(run_launcher directory run_sequence_prompts.sh "$directory_project" "$scratch/prompts.txt")"
[[ "$directory_status" -eq 0 ]] || fail "directory plant exited $directory_status"
[[ "$(cat "$scratch/directory-sentinel")" == keep ]] || fail "host followed a planted directory"
[[ -d "$directory_project/plan/handoffs/conversation_1.txt" ]] || fail "planted directory was removed"
[[ -L "$directory_project/plan/handoffs/conversation_1.txt/conversation_1.txt" ]] ||
    fail "planted child link was replaced"
set_run_dir "$scratch/case-directory-run_sequence_prompts.sh"
assert_private_handoffs "$run_dir"

fifo_project="$scratch/fifo-project"
mkdir -p "$fifo_project/plan/handoffs/workflow_log.txt"
mkfifo "$fifo_project/plan/handoffs/workflow_log.txt/workflow_log.txt"
fifo_status="$(
    LAUNCH_TIMEOUT=15 run_launcher fifo run_sequence_prompts.sh "$fifo_project" "$scratch/prompts.txt"
)"
[[ "$fifo_status" -eq 0 ]] || fail "directory fifo exited $fifo_status"
[[ -p "$fifo_project/plan/handoffs/workflow_log.txt/workflow_log.txt" ]] ||
    fail "planted child fifo was replaced"
set_run_dir "$scratch/case-fifo-run_sequence_prompts.sh"
assert_private_handoffs "$run_dir"

linked_project="$scratch/linked-project"
mkdir -p "$linked_project" "$scratch/outside-plan"
ln -s "$scratch/outside-plan" "$linked_project/plan"
linked_status="$(run_launcher linked run_sequence_prompts.sh "$linked_project" "$scratch/prompts.txt")"
[[ "$linked_status" -eq 0 ]] || fail "linked plan directory exited $linked_status"
[[ -z "$(find "$scratch/outside-plan" -mindepth 1 -print -quit)" ]] || fail "handoffs followed a linked plan directory"
[[ -L "$linked_project/plan" ]] || fail "linked plan directory was replaced"
set_run_dir "$scratch/case-linked-run_sequence_prompts.sh"
assert_private_handoffs "$run_dir"

# Cleanup must handle read-only cache trees and report deletion failures precisely.
printf 'keep\n' > "$scratch/cleanup-sentinel"
chmod 400 "$scratch/cleanup-sentinel"
export DOCKER_MOCK_SENTINEL="$scratch/cleanup-sentinel"
for cleanup_launcher in run_sequence_prompts.sh run_command.sh run.sh; do
    cleanup_arguments=("$project" hello)
    [[ "$cleanup_launcher" != run.sh ]] || cleanup_arguments=("$project")
    [[ "$cleanup_launcher" != run_sequence_prompts.sh ]] || cleanup_arguments=("$project" "$scratch/prompts.txt")
    readonly_status="$(LAUNCH_TIMEOUT=15 run_launcher readonly "$cleanup_launcher" "${cleanup_arguments[@]}")"
    [[ "$readonly_status" -eq 0 ]] || fail "$cleanup_launcher could not delete a read-only home"
    [[ "$(mode_of "$scratch/cleanup-sentinel")" == 400 ]] || fail "cleanup changed a linked file's permissions"
    [[ "$(cat "$scratch/cleanup-sentinel")" == keep ]] || fail "cleanup changed a linked file"
    if [[ "$cleanup_launcher" == run_sequence_prompts.sh ]]; then
        set_run_dir "$scratch/case-readonly-$cleanup_launcher"
        assert_private_handoffs "$run_dir"
    fi
    delete_status="$(run_launcher delete-fail "$cleanup_launcher" "${cleanup_arguments[@]}")"
    [[ "$delete_status" -ne 0 ]] || fail "$cleanup_launcher ignored deletion failure"
    delete_case="$scratch/case-delete-fail-$cleanup_launcher"
    set_run_dir "$delete_case"
    grep -F "could not delete $run_dir/home" "$delete_case/stdout" "$delete_case/stderr" >/dev/null ||
        fail "$cleanup_launcher did not name the failed deletion"
    if grep -F 'removal was not confirmed' "$delete_case/stdout" "$delete_case/stderr" >/dev/null; then
        fail "$cleanup_launcher misreported confirmed container removal"
    fi
    [[ -d "$run_dir/home" && -s "$run_dir/container.id" ]] || fail "failed cleanup lost retry state"
    if [[ "$cleanup_launcher" == run_sequence_prompts.sh ]]; then
        [[ -s "$run_dir/handoffs/conversation_1.txt" ]] || fail "failed cleanup lost handoffs"
    fi
done

# Reject ambiguous state paths before mkdir or docker run can write anything.
for invalid_kind in relative dot dotdot; do
    invalid_base="$scratch/invalid-$invalid_kind"
    mkdir -p "$invalid_base/project"
    case "$invalid_kind" in
        relative) invalid_state="relative-state" ;;
        dot) invalid_state="$invalid_base/missing/./state" ;;
        dotdot) invalid_state="$invalid_base/missing/../project/state" ;;
    esac
    invalid_status="$(
        LAUNCH_STATE_HOME="$invalid_state" \
            run_launcher "invalid-$invalid_kind" run_command.sh "$invalid_base/project" hello
    )"
    [[ "$invalid_status" -ne 0 ]] || fail "$invalid_kind state path was accepted"
    invalid_case="$scratch/case-invalid-$invalid_kind-run_command.sh"
    grep -F 'XDG_STATE_HOME' "$invalid_case/stderr" >/dev/null || fail "missing state path error"
    relative_home="$invalid_case/home"
    [[ ! -e "$invalid_base/missing" && ! -e "$invalid_base/project/state" &&
        ! -e "$relative_home/relative-state" ]] || fail "invalid state path created directories"
    [[ ! -e "$invalid_case/docker.log" ]] || fail "invalid state path started a container"
done

inside_project="$scratch/inside-project"
mkdir -p "$inside_project"
inside_status="$(
    LAUNCH_STATE_HOME="$inside_project/state" \
        run_launcher inside run_sequence_prompts.sh "$inside_project" "$scratch/prompts.txt"
)"
[[ "$inside_status" -ne 0 ]] || fail "state inside the project was accepted"
grep -F 'inside the project' \
    "$scratch/case-inside-run_sequence_prompts.sh/stderr" >/dev/null ||
    fail "state inside the project was not reported"
if [[ -f "$scratch/case-inside-run_sequence_prompts.sh/docker.log" ]] &&
    grep -Fx 'run' "$scratch/case-inside-run_sequence_prompts.sh/docker.log" >/dev/null; then
    fail "state inside the project still started a container"
fi
[[ ! -e "$inside_project/plan" && ! -d "$inside_project/state" ]] ||
    fail "state inside the project wrote project files"

sym_project="$scratch/sym-project"
mkdir -p "$sym_project"
ln -s "$sym_project" "$scratch/link-state"
sym_status="$(
    LAUNCH_STATE_HOME="$scratch/link-state" \
        run_launcher symlink run_sequence_prompts.sh "$sym_project" "$scratch/prompts.txt"
)"
[[ "$sym_status" -ne 0 ]] || fail "state link into the project was accepted"
if [[ -f "$scratch/case-symlink-run_sequence_prompts.sh/docker.log" ]] &&
    grep -Fx 'run' "$scratch/case-symlink-run_sequence_prompts.sh/docker.log" >/dev/null; then
    fail "state link into the project still started a container"
fi

# Name the resolved destination and the setting users must change.
for state_case in inside symlink; do
    state_error="$scratch/case-$state_case-run_sequence_prompts.sh/stderr"
    if [[ "$state_case" == inside ]]; then
        resolved_state="$inside_project/state/claude_code/runs"
    else
        resolved_state="$sym_project/claude_code/runs"
    fi
    grep -F "$resolved_state" "$state_error" >/dev/null || fail "state error omitted the resolved path"
    grep -F 'XDG_STATE_HOME' "$state_error" >/dev/null || fail "state error omitted XDG_STATE_HOME"
done

expect_removal_kept() {
    local script_name="$1"
    local mode="$2"
    shift 2
    local status
    status="$(run_launcher "$mode" "$script_name" "$@")"
    [[ "$status" -ne 0 ]] || fail "${script_name} ${mode} exited 0"
    local case_dir="$scratch/case-${mode}-${script_name}"
    grep -F 'may still be running' "$case_dir/stdout" "$case_dir/stderr" >/dev/null ||
        fail "${script_name} ${mode} did not report a live container"
    grep -F 'removal was not confirmed' "$case_dir/stdout" "$case_dir/stderr" >/dev/null ||
        fail "${script_name} ${mode} did not keep the run directory"
    set_run_dir "$case_dir"
    [[ -d "$run_dir/home" ]] || fail "${script_name} ${mode} deleted the home"
    [[ -s "$run_dir/container.id" ]] || fail "${script_name} ${mode} deleted the container id"
    if [[ "$script_name" == run_sequence_prompts.sh ]]; then
        [[ -d "$run_dir/handoffs" ]] || fail "${script_name} ${mode} deleted handoffs"
        [[ ! -e "$project/plan" ]] || fail "${script_name} ${mode} wrote into the project"
    fi
}

expect_removal_kept run_sequence_prompts.sh rm-fail "$project" "$scratch/prompts.txt"
expect_removal_kept run_command.sh rm-fail "$project" "hello"
expect_removal_kept run.sh rm-fail "$project"
expect_removal_kept run_sequence_prompts.sh daemon-down "$project" "$scratch/prompts.txt"
expect_removal_kept run_command.sh daemon-down "$project" "hello"
expect_removal_kept run_sequence_prompts.sh inspect-fail "$project" "$scratch/prompts.txt"

absent_status="$(run_launcher absent run_sequence_prompts.sh "$project" "$scratch/prompts.txt")"
[[ "$absent_status" -eq 0 ]] || fail "already-absent container exited $absent_status"
grep -Fx "inspect ${container_id}" \
    "$scratch/case-absent-run_sequence_prompts.sh/docker.log" >/dev/null ||
    fail "already-absent container was not checked with the daemon"
set_run_dir "$scratch/case-absent-run_sequence_prompts.sh"
assert_private_handoffs "$run_dir"
absent_command="$(run_launcher absent run.sh "$project")"
[[ "$absent_command" -eq 0 ]] || fail "already-absent run.sh exited $absent_command"
if [[ -n "$(find "$scratch/case-absent-run.sh/xdg" -type d -name 'run.*' -print -quit)" ]]; then
    fail "already-absent run.sh kept an empty run directory"
fi

bad_status="$(run_launcher bad-id run_sequence_prompts.sh "$project" "$scratch/prompts.txt")"
[[ "$bad_status" -ne 0 ]] || fail "invalid container id exited 0"
if grep -E '^(removed|rm-failed|removed-by-name) ' \
    "$scratch/case-bad-id-run_sequence_prompts.sh/docker.log" >/dev/null; then
    fail "invalid container id was removed"
fi
set_run_dir "$scratch/case-bad-id-run_sequence_prompts.sh"
[[ -d "$run_dir/home" && -d "$run_dir/handoffs" ]] || fail "invalid container id deleted the run"
[[ "$(cat "$run_dir/container.id")" == not-an-id ]] || fail "invalid container id file was not kept"

grep -Fx 'COPY --chmod=0644 managed-settings.json /etc/claude-code/managed-settings.json' \
    "$repository_root/container/Dockerfile" >/dev/null || fail "managed settings mode is not fixed"

echo "Launch checks passed."
