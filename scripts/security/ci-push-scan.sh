#!/usr/bin/env bash
# Scan the CI revision range for sensitive commit messages and added lines.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
range="$(bash "${script_dir}/ci-range.sh")"

if [[ "$range" == *..* ]]; then
  from="${range%%..*}"
  to="${range#*..}"
  exec bash "${script_dir}/check-push-range.sh" --from "$from" --to "$to"
fi

if [[ "$range" == *^! ]]; then
  exec bash "${script_dir}/check-push-range.sh" --only --to "${range%^!}"
fi

echo "error: unsupported push range" >&2
exit 1
