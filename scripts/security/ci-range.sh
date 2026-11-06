#!/usr/bin/env bash
# Print a git revision range for this GitHub Actions event.
# An empty, zero, or unknown push base uses the reviewed baseline when that
# commit is an ancestor of the target. Otherwise the range is all history.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SECURITY_SCRIPT_DIR="$script_dir"
# shellcheck source=scripts/security/reviewed-range.sh
source "$script_dir/reviewed-range.sh"

if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
  if [[ -z "${PR_BASE_SHA:-}" || -z "${PR_HEAD_SHA:-}" ]]; then
    echo "error: pull request range is missing" >&2
    exit 1
  fi
  printf '%s..%s\n' "${PR_BASE_SHA}" "${PR_HEAD_SHA}"
  exit 0
fi

target="${GITHUB_SHA:-}"
if [[ -z "$target" ]]; then
  echo "error: GITHUB_SHA is missing" >&2
  exit 1
fi

before="${PUSH_BEFORE_SHA:-}"
if [[ -n "$before" && ! "$before" =~ ^0+$ ]] && git cat-file -e "${before}^{commit}" 2>/dev/null; then
  printf '%s..%s\n' "$before" "$target"
else
  reviewed_fallback_range "$target"
fi
