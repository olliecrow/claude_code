#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/claude_common_lib.sh"

usage() {
  cat <<EOF
Usage:
  $(basename "$0")

Description:
  Run non-mutating preflight checks for the Claude Code container workflow.
EOF
}

if [[ $# -ne 0 ]]; then
  usage
  exit 1
fi

exit_code=0

report_ok() {
  local name="$1"
  local detail="$2"
  echo "[ok] $name: $detail"
}

report_fail() {
  local name="$1"
  local detail="$2"
  echo "[fail] $name: $detail"
  exit_code=1
}

check_tool() {
  local tool="$1"
  if path="$(command -v "$tool" 2>/dev/null)"; then
    report_ok "tool $tool" "$path"
  else
    report_fail "tool $tool" "not found in PATH"
  fi
}

echo "claude_code container doctor"
echo

check_tool docker

if check_claude_auth >/dev/null 2>&1; then
  report_ok "host claude auth dir" "$HOME/.claude"
else
  report_fail "host claude auth dir" "missing, run claude login on host first"
fi

if docker info >/dev/null 2>&1; then
  report_ok "docker daemon" "reachable"
else
  report_fail "docker daemon" "unreachable, start Docker and retry"
fi

if docker image inspect claude_code_container >/dev/null 2>&1; then
  report_ok "image claude_code_container" "present"
else
  report_fail "image claude_code_container" "missing, run ./container/build.sh"
fi

if [[ "$exit_code" -eq 0 ]]; then
  echo
  echo "doctor result: PASS"
  exit 0
fi

echo
echo "doctor result: FAIL"
exit 1
