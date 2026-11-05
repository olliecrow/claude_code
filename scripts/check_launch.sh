#!/usr/bin/env bash
# Mock Docker checks for auth forwarding and failed container startup.
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
library="$repository_root/container/claude_common_lib.sh"

unset CLAUDE_CODE_OAUTH_TOKEN ANTHROPIC_API_KEY CLAUDE_CONTAINER_MOUNT_HOST_CONFIG || true

scratch="$(mktemp -d)"
cleanup() {
    rm -rf -- "$scratch"
}
trap cleanup EXIT

fail() {
    echo "launch check failed: $1" >&2
    exit 1
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
    info|image)
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
        if [[ "$mode" == "start-fail" ]]; then
            [[ -n "$cidfile" ]] || exit 2
            printf '%s\n' "${DOCKER_MOCK_ID:?}" > "$cidfile"
            printf '%s\n' "$cidfile" > "$state/cidfile-path"
            printf 'created\n' >> "$log"
            exit 125
        fi
        if [[ "$mode" == "create-fail" ]]; then
            printf 'create-failed\n' >> "$log"
            exit 125
        fi
        exit 2
        ;;
    rm)
        printf 'removed %s\n' "${3:-}" >> "$log"
        cidfile="$(cat "$state/cidfile-path")"
        if [[ -d "$(dirname "$cidfile")/home" ]]; then
            printf 'home-present\n' >> "$log"
        else
            printf 'home-missing\n' >> "$log"
        fi
        exit 0
        ;;
    *)
        printf 'unexpected %s\n' "$1" >> "$log"
        exit 2
        ;;
esac
EOF
chmod 755 "$mock_bin/docker"

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

# A planted fsmonitor must never run on the host during sequence preflight.
git init -q "$project"
printf '#!/bin/sh\ntouch "%s"\n' "$scratch/fsmonitor-ran" > "$scratch/fsmonitor"
chmod 755 "$scratch/fsmonitor"
git -C "$project" config core.fsmonitor "$scratch/fsmonitor"
# Stop after Git preflight without starting Docker or using real credentials.
if env HOME="$scratch/dry-home" CLAUDE_TIMEOUT_SECONDS=1 \
    bash "$repository_root/container/run_sequence_prompts.sh" "$project" "$scratch/prompts.txt" \
    > "$scratch/preflight.out" 2>&1; then
    fail "preflight without authentication passed"
fi
[[ ! -e "$scratch/fsmonitor-ran" ]] || fail "host ran planted fsmonitor"

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
    env \
        HOME="$fake_home" \
        TMPDIR="$temp_root" \
        PATH="$mock_bin:$PATH" \
        CLAUDE_CODE_OAUTH_TOKEN=dummyoauth \
        DOCKER_MOCK_LOG="$log" \
        DOCKER_MOCK_MODE="$mode" \
        DOCKER_MOCK_ID="$container_id" \
        DOCKER_MOCK_STATE="$state" \
        bash "$repository_root/container/$script_name" "$@" \
        > "$case_dir/stdout" 2> "$case_dir/stderr" || status=$?
    printf '%s\n' "$status"
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

echo "Launch checks passed."
