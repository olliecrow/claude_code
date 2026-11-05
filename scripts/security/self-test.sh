#!/usr/bin/env bash
# Prove the sensitive-text and push-range checks reject the known bypasses.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
text_check="$script_dir/check-sensitive-text.sh"
range_check="$script_dir/check-push-range.sh"
range_script="$script_dir/ci-range.sh"
scan_script="$script_dir/ci-push-scan.sh"
scratch="$(mktemp -d)"
trap 'rm -rf -- "$scratch"' EXIT

fail() {
    echo "security self-test failed: $1" >&2
    exit 1
}

# Build path text in the temp files only. The checker scans this script too.
printf -v bad_home '/%s/%s' 'home' 'userbob'
printf -v bad_developer '/%s/%s' 'home' 'developer'
printf -v bad_user '/%s/%s' 'Users' 'YOUNG'
backslash="$(printf '\134')"
printf -v bad_windows 'C:%sUsers%s%s' "$backslash" "$backslash" 'alice'
printf -v placeholder_windows 'C:%sUsers%s%s' "$backslash" "$backslash" 'YOU'

write_text() {
    local path="$1"
    local content="$2"
    printf '%s\n' "$content" > "$path"
}

expect_path_rejected() {
    local label="$1"
    local path="$2"
    local output=""
    local status=0
    output="$(bash "$text_check" --context=self-test "$path" 2>&1)" || status=$?
    [[ "$status" -ne 0 ]] || fail "$label was accepted"
    [[ "$output" == *"local machine path"* ]] || fail "$label was not reported as a path"
}

expect_secret_rejected() {
    local label="$1"
    local path="$2"
    local output=""
    local status=0
    output="$(bash "$text_check" --context=self-test "$path" 2>&1)" || status=$?
    [[ "$status" -ne 0 ]] || fail "$label was accepted"
    [[ "$output" == *"credential-like assignment"* ]] || fail "$label was not reported as a credential"
}

expect_text_ok() {
    local label="$1"
    local path="$2"
    if ! bash "$text_check" --context=self-test "$path" >/dev/null 2>&1; then
        fail "$label was rejected"
    fi
}

safe_file="$scratch/safe.txt"
write_text "$safe_file" '/Users/YOU'
printf '%s\n' '/home/dev' >> "$safe_file"
printf 'token = self._stage_token(workflow_type)\n' >> "$safe_file"
expect_text_ok "placeholders and function assignment" "$safe_file"

write_text "$scratch/young.txt" "/${bad_user}"
expect_path_rejected "prefix of /Users/YOU" "$scratch/young.txt"

write_text "$scratch/userbob.txt" "$bad_home"
expect_path_rejected "home directory name" "$scratch/userbob.txt"

write_text "$scratch/developer.txt" "$bad_developer"
expect_path_rejected "prefix of /home/dev" "$scratch/developer.txt"

write_text "$scratch/windows.txt" "$bad_windows"
expect_path_rejected "windows profile path" "$scratch/windows.txt"

write_text "$scratch/mixed.txt" "/Users/YOU ${bad_home}"
expect_path_rejected "real path beside a placeholder" "$scratch/mixed.txt"

write_text "$scratch/windows-ok.txt" "$placeholder_windows"
expect_text_ok "windows placeholder" "$scratch/windows-ok.txt"

printf 'token=%s\n' 'abc123456789XYZ' > "$scratch/secret.txt"
expect_secret_rejected "assigned credential" "$scratch/secret.txt"

missing_status=0
bash "$text_check" --context=self-test "$scratch/missing.txt" >/dev/null 2>&1 || missing_status=$?
[[ "$missing_status" -eq 2 ]] || fail "missing file exited ${missing_status}"

zero_ref="0000000000000000000000000000000000000000"
fake_from="$(printf 'a%.0s' {1..40})"
fake_to="$(printf 'b%.0s' {1..40})"
bad_range_status=0
bash "$range_check" --from "$fake_from" --to "$fake_to" >/dev/null 2>&1 || bad_range_status=$?
[[ "$bad_range_status" -ne 0 ]] || fail "unknown commit range was accepted"
name_status=0
bash "$range_check" --from HEAD --to HEAD >/dev/null 2>&1 || name_status=$?
[[ "$name_status" -ne 0 ]] || fail "non-sha range was accepted"
if ! bash "$range_check" --to "$zero_ref" >/dev/null 2>&1; then
    fail "deleted ref was not skipped"
fi
unset PRE_COMMIT_FROM_REF PRE_COMMIT_TO_REF PRE_COMMIT_LOCAL_BRANCH || true
empty_status=0
bash "$range_check" >/dev/null 2>&1 || empty_status=$?
[[ "$empty_status" -ne 0 ]] || fail "missing push range was accepted"

repo="$scratch/repo"
git init -q -b main "$repo"
commit_file() {
    local name="$1"
    local content="$2"
    local message="$3"
    printf '%s\n' "$content" > "$repo/$name"
    git -C "$repo" add -- "$name"
    git -C "$repo" \
        -c user.name='Policy Test' \
        -c user.email='policy-test@example.com' \
        -c commit.gpgsign=false \
        commit -q -m "$message"
}

commit_file note.txt 'ok' 'base'
base_sha="$(git -C "$repo" rev-parse HEAD)"
commit_file note.txt "++ ${bad_home}" 'plus lines'
plus_sha="$(git -C "$repo" rev-parse HEAD)"
plus_status=0
(
    cd "$repo"
    bash "$range_check" --from "$base_sha" --to "$plus_sha"
) >/dev/null 2>&1 || plus_status=$?
[[ "$plus_status" -ne 0 ]] || fail "added line starting with ++ was accepted"

commit_file note.txt '/home/dev' 'placeholder'
placeholder_sha="$(git -C "$repo" rev-parse HEAD)"
(
    cd "$repo/."
    bash "$range_check" --from "$plus_sha" --to "$placeholder_sha"
) || fail "placeholder commit was rejected"

git -C "$repo" checkout -q -b side
commit_file side.txt 'side only' 'side'
git -C "$repo" checkout -q main
git -C "$repo" merge -q --no-ff --no-commit side >/dev/null 2>&1
printf '%s\n' "$bad_home" > "$repo/secret.txt"
git -C "$repo" add -- secret.txt
git -C "$repo" \
    -c user.name='Policy Test' \
    -c user.email='policy-test@example.com' \
    -c commit.gpgsign=false \
    commit -q -m 'merge'
merge_sha="$(git -C "$repo" rev-parse HEAD)"
merge_parent="$(git -C "$repo" rev-parse HEAD^1)"
merge_status=0
(
    cd "$repo"
    bash "$range_check" --from "$merge_parent" --to "$merge_sha"
) >/dev/null 2>&1 || merge_status=$?
[[ "$merge_status" -ne 0 ]] || fail "merge commit addition was accepted"
only_status=0
(
    cd "$repo"
    bash "$range_check" --only --to "$merge_sha"
) >/dev/null 2>&1 || only_status=$?
[[ "$only_status" -ne 0 ]] || fail "single merge commit was accepted"

subdir="$repo/nested"
mkdir -p "$subdir"
sub_status=0
(
    cd "$subdir"
    bash "$range_check" --from "$merge_parent" --to "$merge_sha"
) >/dev/null 2>&1 || sub_status=$?
[[ "$sub_status" -ne 0 ]] || fail "scan from a subdirectory missed the merge"

export GITHUB_EVENT_NAME=push
export GITHUB_REF_NAME=main
export GITHUB_SHA="$placeholder_sha"
export PUSH_BEFORE_SHA=""
empty_before="$(
    cd "$repo"
    bash "$range_script"
)"
[[ "$empty_before" == "${placeholder_sha}^!" ]] || fail "empty before produced ${empty_before}"
export PUSH_BEFORE_SHA="$zero_ref"
zero_before="$(
    cd "$repo"
    bash "$range_script"
)"
[[ "$zero_before" == "${placeholder_sha}^!" ]] || fail "zero before produced ${zero_before}"
export PUSH_BEFORE_SHA="$fake_from"
missing_before="$(
    cd "$repo"
    bash "$range_script"
)"
[[ "$missing_before" == "${placeholder_sha}^!" ]] || fail "unknown before produced ${missing_before}"
git -C "$repo" log --diff-merges=first-parent "$missing_before" >/dev/null || fail "fallback range is not a valid git range"
export PUSH_BEFORE_SHA="$base_sha"
export GITHUB_SHA="$plus_sha"
known_before="$(
    cd "$repo"
    bash "$range_script"
)"
[[ "$known_before" == "${base_sha}..${plus_sha}" ]] || fail "known before produced ${known_before}"
export GITHUB_EVENT_NAME=pull_request
export PR_BASE_SHA="$base_sha"
export PR_HEAD_SHA="$plus_sha"
pr_range="$(
    cd "$repo"
    bash "$range_script"
)"
[[ "$pr_range" == "${base_sha}..${plus_sha}" ]] || fail "pull request range produced ${pr_range}"

export GITHUB_EVENT_NAME=push
unset PR_BASE_SHA PR_HEAD_SHA || true
export GITHUB_SHA="$merge_sha"
export PUSH_BEFORE_SHA=""
ci_status=0
(
    cd "$repo"
    bash "$scan_script"
) >/dev/null 2>&1 || ci_status=$?
[[ "$ci_status" -ne 0 ]] || fail "CI scan of a missing base accepted the merge commit"

export PUSH_BEFORE_SHA="$merge_parent"
parent_status=0
(
    cd "$repo"
    bash "$scan_script"
) >/dev/null 2>&1 || parent_status=$?
[[ "$parent_status" -ne 0 ]] || fail "CI scan of the merge range was accepted"

echo "Security self-test passed."
