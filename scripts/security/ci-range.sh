#!/usr/bin/env bash
# Print a git revision range for this GitHub Actions event.
# A missing, zero, or unknown push base scans all commits reachable from the target.
set -euo pipefail

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
  printf '%s\n' "$target"
fi
