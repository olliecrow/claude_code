#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/claude_common_lib.sh"

usage() {
  cat <<EOF
Usage:
  $(basename "$0") /path/to/project [--shell]

Description:
  Print the Claude Code container execution plan without starting Docker.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 1
fi

REPO_DIR="$1"
MODE="${2:-}"

if [[ -n "$MODE" && "$MODE" != "--shell" ]]; then
  echo "Error: unsupported mode '$MODE'" >&2
  usage
  exit 1
fi

if ! validate_directory "$REPO_DIR"; then
  exit 1
fi

if ! check_claude_auth >/dev/null 2>&1; then
  echo "Error: missing host Claude auth at ~/.claude" >&2
  exit 1
fi

REPO_DIR="$(get_absolute_path "$REPO_DIR")"
HOST_TZ="$(detect_host_timezone)"
container_name="claude_code_$(basename "$REPO_DIR")_<pid>"
mode_label="launch claude"
if [[ "$MODE" == "--shell" ]]; then
  mode_label="interactive shell"
fi

echo "claude_code container dry-run"
echo "repo: $REPO_DIR"
echo "mode: $mode_label"
echo "container name: $container_name"
echo

echo "planned sequence:"
echo "1. Validate local prerequisites: docker available, repo path exists, and host auth at ~/.claude."
echo "2. Merge container settings for the target project path."
echo "3. Start detached container with project and ~/.claude bind mounts."
if [[ -n "$HOST_TZ" ]]; then
  echo "4. Pass host timezone to container as TZ=$HOST_TZ."
else
  echo "4. Skip timezone injection because host timezone was not detected."
fi
if [[ "$MODE" == "--shell" ]]; then
  echo "5. Open login shell inside container."
else
  echo "5. Launch Claude in /workspace with configured model and permissions flags."
fi
echo "6. Remove container and restore local settings when session ends."
echo

echo "docker run preview:"
echo "docker run -d --name \"$container_name\" \\"
echo "  --mount type=bind,source=\"$REPO_DIR\",target=/workspace \\"
echo "  --mount type=bind,source=\"$HOME/.claude\",target=/home/dev/.claude \\"
echo "  $(get_base_docker_env_args) \\"
if [[ -n "$HOST_TZ" ]]; then
  echo "  --env TZ=\"$HOST_TZ\" \\"
fi
echo "  claude_code_container tail -f /dev/null"
echo

echo "dry-run only: no Docker commands were executed."
