#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repository_root"

for required_tool in python3 shellcheck uv; do
    if ! command -v "$required_tool" >/dev/null 2>&1; then
        echo "Error: required check tool is missing: $required_tool" >&2
        exit 1
    fi
done

shell_scripts=(
    container/build.sh
    container/claude_common_lib.sh
    container/doctor.sh
    container/dry_run.sh
    container/run.sh
    container/run_command.sh
    container/run_sequence_prompts.sh
    scripts/check.sh
    scripts/security/check-push-range.sh
    scripts/security/check-sensitive-text.sh
)

bash -n "${shell_scripts[@]}"
shellcheck --severity=style "${shell_scripts[@]}"
python3 scripts/check_assets.py
uv lock --check --project container

temporary_directory="$(mktemp -d)"
cleanup() {
    rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

repository_files=()
while IFS= read -r -d '' repository_file; do
    repository_files+=("$repository_file")
done < <(git ls-files --cached --others --exclude-standard -z)

bash scripts/security/check-sensitive-text.sh \
    --context=current-tree \
    "${repository_files[@]}"

safe_text="$temporary_directory/safe.txt"
unsafe_text="$temporary_directory/unsafe.txt"
printf '%s\n' \
    'Use /Users/YOU as the documented placeholder.' \
    'token = self._stage_token(workflow_type)' \
    > "$safe_text"
printf 'token=%s\n' 'abc123456789XYZ' > "$unsafe_text"

bash scripts/security/check-sensitive-text.sh --context=self-test "$safe_text"
if bash scripts/security/check-sensitive-text.sh --context=self-test "$unsafe_text" >/dev/null 2>&1; then
    echo "Error: sensitive-text self-test did not reject an unsafe value." >&2
    exit 1
fi

echo "Repository checks passed."
