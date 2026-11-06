#!/usr/bin/env bash
# Prove the sensitive-text and push-range checks reject the known bypasses.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
text_check="$script_dir/check-sensitive-text.sh"
range_check="$script_dir/check-push-range.sh"
range_script="$script_dir/ci-range.sh"
scan_script="$script_dir/ci-push-scan.sh"
gitleaks_wrapper="$script_dir/gitleaks-range.sh"
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

# Generate token fixtures at runtime; never store a complete token in source.
for prefix in sk-ant-oat01 sk-ant-api03 sk-proj ghp gho ghu ghs ghr github_pat; do
    separator=-
    [[ "$prefix" == gh* || "$prefix" == github_pat ]] && separator=_
    token_file="$scratch/${prefix}.txt"
    printf '%s%s%s\n' "$prefix" "$separator" "$(printf 'aB7x%.0s' {1..24})" > "$token_file"
    token_status=0
    bash "$text_check" "$token_file" >/dev/null 2>&1 || token_status=$?
    [[ "$token_status" -eq 1 ]] || fail "$prefix token was accepted"
done
printf '%s.%s.%s\n' "eyJ$(printf 'a%.0s' {1..20})" "$(printf 'b%.0s' {1..20})" "$(printf 'c%.0s' {1..20})" > "$scratch/jwt.txt"
jwt_status=0
bash "$text_check" "$scratch/jwt.txt" >/dev/null 2>&1 || jwt_status=$?
[[ "$jwt_status" -eq 1 ]] || fail "JWT was accepted"
# Token rules need a left boundary, so ordinary hyphenated words pass.
word_text='See the risk-assessment-for-the-project-plan and task-list-item-with-long-name notes.'
write_text "$scratch/words.txt" "$word_text"
expect_text_ok "words containing sk-" "$scratch/words.txt"

if command -v gitleaks >/dev/null 2>&1; then
    config="$script_dir/../../.gitleaks.toml"
    leak_fixture="$scratch/leak-fixture"
    mkdir "$leak_fixture"
    check_gitleaks() {
        local expected="$1" label="$2" content="$3" status=0
        printf '%s\n' "$content" > "$leak_fixture/note.txt"
        gitleaks dir --no-banner --redact --config "$config" "$leak_fixture" >/dev/null 2>&1 || status=$?
        [[ "$status" -eq "$expected" ]] || fail "gitleaks $label exited $status, expected $expected"
    }
    check_gitleaks 1 home "$bad_home"
    check_gitleaks 1 developer "$bad_developer"
    check_gitleaks 1 users "$bad_user"
    check_gitleaks 1 windows "$bad_windows"
    check_gitleaks 1 mixed "/home/dev $bad_home"
    check_gitleaks 0 placeholders "/home/dev/x /Users/YOU/x $placeholder_windows"
    check_gitleaks 1 oauth "$(cat "$scratch/sk-ant-oat01.txt")"
    check_gitleaks 1 api "$(cat "$scratch/sk-ant-api03.txt")"
    check_gitleaks 1 openai "$(cat "$scratch/sk-proj.txt")"
    check_gitleaks 1 "openai after text" "key: $(cat "$scratch/sk-proj.txt")"
    check_gitleaks 1 jwt "$(cat "$scratch/jwt.txt")"
    check_gitleaks 0 words "$word_text"
else
    echo "Gitleaks fixture checks skipped: gitleaks is not installed."
fi

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
git -C "$repo" config user.name 'Policy Test'
git -C "$repo" config user.email 'policy-test@example.com'
git -C "$repo" config commit.gpgsign false
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
merge_setup=0
git -C "$repo" merge -q --no-ff --no-commit side >/dev/null 2>&1 || merge_setup=$?
[[ "$merge_setup" -eq 0 ]] || fail "test merge exited ${merge_setup}"
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

# The gitleaks wrapper must fail closed: gitleaks itself exits 0 when git
# cannot read the range.
expect_wrapper() {
    local expected="$1" label="$2" status=0
    shift 2
    (cd "$repo"; "$@") >/dev/null 2>&1 || status=$?
    [[ "$status" -eq "$expected" ]] || fail "gitleaks wrapper $label exited $status, expected $expected"
}
fake_bin="$scratch/fake-gitleaks"
mkdir "$fake_bin"
cat > "$fake_bin/gitleaks" <<'EOF'
#!/usr/bin/env bash
if [[ "${FAKE_GITLEAKS_MODE:?}" == error ]]; then
    echo '12:00AM ERR [git] fatal: ambiguous argument'
    echo '12:00AM INF 1 commits scanned.'
else
    echo '12:00AM INF 0 commits scanned.'
fi
echo '12:00AM INF no leaks found'
EOF
chmod 755 "$fake_bin/gitleaks"
for fake_mode in error zero; do
    expect_wrapper 2 "fake $fake_mode" env PATH="$fake_bin:$PATH" FAKE_GITLEAKS_MODE="$fake_mode" \
        bash "$gitleaks_wrapper" --from "$base_sha" --to "$plus_sha"
done
expect_wrapper 2 "unknown base" bash "$gitleaks_wrapper" --from "$fake_from" --to "$plus_sha"
expect_wrapper 2 "base with a space" bash "$gitleaks_wrapper" --from "$base_sha " --to "$plus_sha"
expect_wrapper 2 "name target" bash "$gitleaks_wrapper" --to HEAD
expect_wrapper 2 "missing target" bash "$gitleaks_wrapper"
if command -v gitleaks >/dev/null 2>&1; then
    expect_wrapper 0 "clean range" bash "$gitleaks_wrapper" --from "$plus_sha" --to "$placeholder_sha"
    expect_wrapper 1 "merge addition" bash "$gitleaks_wrapper" --from "$merge_parent" --to "$merge_sha"
    expect_wrapper 0 "empty range" bash "$gitleaks_wrapper" --from "$merge_sha" --to "$merge_sha"
fi

# A binary attribute or NUL byte must not hide a changed secret.
for binary_kind in attribute nul; do
    previous_sha="$(git -C "$repo" rev-parse HEAD)"
    if [[ "$binary_kind" == attribute ]]; then
        commit_file .gitattributes 'binary.txt -diff' 'binary attribute'
    fi
    printf '%s/%s\n' "$bad_home" "$binary_kind" > "$repo/binary.txt"
    [[ "$binary_kind" != nul ]] || printf '\0' >> "$repo/binary.txt"
    git -C "$repo" add binary.txt
    git -C "$repo" commit -qm "binary $binary_kind"
    binary_sha="$(git -C "$repo" rev-parse HEAD)"
    binary_status=0
    (cd "$repo"; bash "$range_check" --from "$previous_sha" --to "$binary_sha") >/dev/null 2>&1 || binary_status=$?
    [[ "$binary_status" -eq 1 ]] || fail "$binary_kind bypass was accepted"
    if command -v gitleaks >/dev/null 2>&1; then
        expect_wrapper 1 "$binary_kind bypass" bash "$gitleaks_wrapper" --from "$previous_sha" --to "$binary_sha"
    fi
done

# A clean tip must not hide a leak in an earlier commit, even on a remote ref.
commit_file binary.txt 'clean' 'clean tip'
clean_sha="$(git -C "$repo" rev-parse HEAD)"
git -C "$repo" update-ref refs/remotes/origin/main "$clean_sha"
for missing_base in '' "$zero_ref"; do
    history_status=0
    (cd "$repo"; bash "$range_check" --from "$missing_base" --to "$clean_sha") >/dev/null 2>&1 || history_status=$?
    [[ "$history_status" -eq 1 ]] || fail "missing base skipped earlier commits"
done

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
[[ "$empty_before" == "${placeholder_sha}" ]] || fail "empty before produced ${empty_before}"
export PUSH_BEFORE_SHA="$zero_ref"
zero_before="$(
    cd "$repo"
    bash "$range_script"
)"
[[ "$zero_before" == "${placeholder_sha}" ]] || fail "zero before produced ${zero_before}"
export PUSH_BEFORE_SHA="$fake_from"
missing_before="$(
    cd "$repo"
    bash "$range_script"
)"
[[ "$missing_before" == "${placeholder_sha}" ]] || fail "unknown before produced ${missing_before}"
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

# gitleaks does not count a commit that only deletes lines; that is not an error.
git -C "$repo" rm -q side.txt
git -C "$repo" commit -qm 'delete only'
delete_sha="$(git -C "$repo" rev-parse HEAD)"
if command -v gitleaks >/dev/null 2>&1; then
    expect_wrapper 0 "delete-only range" bash "$gitleaks_wrapper" --from "$clean_sha" --to "$delete_sha"
fi

# Missing push bases scan after the reviewed baseline, not all history.
# A baseline that is missing or not an ancestor still scans all history.
recorded_base="$(tr -d '[:space:]' < "$script_dir/reviewed-base")"
[[ "$recorded_base" =~ ^[0-9a-f]{40}$ ]] || fail "reviewed baseline is not a commit id"
git -C "$script_dir/../.." merge-base --is-ancestor "$recorded_base" HEAD ||
    fail "reviewed baseline is not an ancestor of HEAD"

baseline_repo="$scratch/baseline-repo"
git init -q -b main "$baseline_repo"
git -C "$baseline_repo" config user.name 'Policy Test'
git -C "$baseline_repo" config user.email 'policy-test@example.com'
git -C "$baseline_repo" config commit.gpgsign false
baseline_commit() {
    local name="$1"
    local content="$2"
    local message="$3"
    printf '%s\n' "$content" > "$baseline_repo/$name"
    git -C "$baseline_repo" add -- "$name"
    git -C "$baseline_repo" \
        -c user.name='Policy Test' \
        -c user.email='policy-test@example.com' \
        -c commit.gpgsign=false \
        commit -q -m "$message"
}
baseline_status() {
    local expected="$1"
    local label="$2"
    shift 2
    local status=0
    (cd "$baseline_repo" && "$@") >/dev/null 2>&1 || status=$?
    [[ "$status" -eq "$expected" ]] || fail "$label exited $status, expected $expected"
}
baseline_commit old.txt "$bad_home" 'old fixture'
baseline_commit reviewed.txt 'reviewed clean' 'reviewed'
reviewed_sha="$(git -C "$baseline_repo" rev-parse HEAD)"
baseline_commit after.txt 'after review' 'after review'
clean_tip="$(git -C "$baseline_repo" rev-parse HEAD)"
mkdir -p "$baseline_repo/scripts/security"
for security_name in ci-range.sh check-push-range.sh check-sensitive-text.sh reviewed-range.sh ci-push-scan.sh gitleaks-range.sh; do
    cp "$script_dir/$security_name" "$baseline_repo/scripts/security/$security_name"
done
cp "$script_dir/../../.gitleaks.toml" "$baseline_repo/.gitleaks.toml"
printf '%s\n' "$reviewed_sha" > "$baseline_repo/scripts/security/reviewed-base"
for missing_base in '' "$zero_ref" "$fake_from"; do
    baseline_status 0 "baseline fallback $missing_base" \
        bash scripts/security/check-push-range.sh --from "$missing_base" --to "$clean_tip"
    fallback_range="$(
        cd "$baseline_repo"
        GITHUB_EVENT_NAME=push PUSH_BEFORE_SHA="$missing_base" GITHUB_SHA="$clean_tip" \
            bash scripts/security/ci-range.sh
    )"
    [[ "$fallback_range" == "$reviewed_sha..$clean_tip" ]] ||
        fail "baseline fallback range was $fallback_range"
    [[ "$(git -C "$baseline_repo" rev-list --count "$fallback_range")" == 1 ]] ||
        fail "baseline fallback included history"
done
baseline_status 0 "pre-push fallback" \
    env -u PRE_COMMIT_FROM_REF -u PRE_COMMIT_LOCAL_BRANCH \
        PRE_COMMIT_TO_REF="$clean_tip" bash scripts/security/check-push-range.sh
baseline_status 1 "full history still scans the old fixture" \
    bash scripts/security/check-push-range.sh --all --to "$clean_tip"
rm "$baseline_repo/scripts/security/reviewed-base"
baseline_status 1 "missing baseline file scans all history" \
    bash scripts/security/check-push-range.sh --from "" --to "$clean_tip"
printf '%s\n' "$fake_from" > "$baseline_repo/scripts/security/reviewed-base"
baseline_status 1 "non-ancestor baseline scans all history" \
    bash scripts/security/check-push-range.sh --from "" --to "$clean_tip"
printf '%s\n' "$reviewed_sha" > "$baseline_repo/scripts/security/reviewed-base"
baseline_commit later.txt "$bad_home" 'later fixture'
later_sha="$(git -C "$baseline_repo" rev-parse HEAD)"
for missing_base in '' "$zero_ref" "$fake_from"; do
    baseline_status 1 "new violation after baseline $missing_base" \
        bash scripts/security/check-push-range.sh --from "$missing_base" --to "$later_sha"
done
baseline_status 1 "known base scans a new violation" \
    bash scripts/security/check-push-range.sh --from "$clean_tip" --to "$later_sha"
if command -v gitleaks >/dev/null 2>&1; then
    baseline_status 0 "gitleaks baseline range" \
        bash scripts/security/gitleaks-range.sh --from "$reviewed_sha" --to "$clean_tip"
    baseline_status 1 "gitleaks new violation" \
        bash scripts/security/gitleaks-range.sh --from "$reviewed_sha" --to "$later_sha"
    baseline_status 0 "CI scan uses the baseline" \
        env GITHUB_EVENT_NAME=push GITHUB_SHA="$clean_tip" PUSH_BEFORE_SHA="" \
            bash scripts/security/ci-push-scan.sh
    baseline_status 1 "CI scan rejects a new violation" \
        env GITHUB_EVENT_NAME=push GITHUB_SHA="$later_sha" PUSH_BEFORE_SHA="" \
            bash scripts/security/ci-push-scan.sh
fi

echo "Security self-test passed."
