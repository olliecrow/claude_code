#!/usr/bin/env bash
# Scan the CI revision range: commit messages and added lines, then gitleaks.
# An empty base scans every commit reachable from the target.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
range="$(bash "${script_dir}/ci-range.sh")"

if [[ "$range" == *..* ]]; then
  from="${range%%..*}"
  to="${range#*..}"
elif [[ "$range" =~ ^([0-9a-f]{40}|[0-9a-f]{64})$ ]]; then
  from=""
  to="$range"
else
  echo "error: unsupported push range" >&2
  exit 1
fi

bash "${script_dir}/check-push-range.sh" --from "$from" --to "$to"
bash "${script_dir}/gitleaks-range.sh" --from "$from" --to "$to"
