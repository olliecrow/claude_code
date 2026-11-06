# Project decisions

## Plain English and clear names

The project uses short, direct language and descriptive names in prompts, docs, code, and maintenance work. This keeps reusable instructions easy to understand and reduces unsafe guesses when scripts are changed.

Enforcement lives in `AGENTS.md`.

## Container trust boundary

The container is a convenient isolated runtime for trusted work, not a strong sandbox for untrusted code.

Claude needs network access, project write access, and authentication for the workflows this repository supports. The launch scripts therefore mount the project read-write and bypass Claude permission prompts. On macOS, container authentication must be supplied separately because Docker cannot read the host Keychain. Blocking common Git commands reduces accidental repository operations but cannot stop arbitrary code from reading mounted data or downloading another Git client.

The host `~/.claude` is not mounted by default. It holds credentials, every session transcript, history, MCP tokens, and settings, and a bypassed session with network access could read or change all of it. Each run gets a new temporary home with only the credentials it needs. Mounting the host config is an explicit opt-in (`CLAUDE_CONTAINER_MOUNT_HOST_CONFIG=1`).

When both `CLAUDE_CODE_OAUTH_TOKEN` and `ANTHROPIC_API_KEY` are set, the launcher forwards only the OAuth token. The API key stays on the host. Cleanup removes the container id this run created, including when startup fails, only after `docker rm` succeeds or the daemon shows that exact id is gone. It then deletes the temporary home. If removal is not confirmed, the script exits non-zero and keeps the private run directory. Sequence handoffs are written only in that directory (`${XDG_STATE_HOME:-$HOME/.local/state}/claude_code/runs/`), never into the project, and they are kept after the run.

The container runs as the host uid so project files keep their owner and a mode-600 credentials file stays readable. It drops all Linux capabilities and sets `no-new-privileges`. Claude Code refuses bypass mode as root, so the scripts do not fall back to root. Settings that must hold in every container session live in the image at `/etc/claude-code/managed-settings.json`.

The README must state this boundary plainly. Do not describe the runtime as secure against malicious projects or prompts.

## Current model selection

Runtime scripts and agent definitions select `claude-opus-5-5` explicitly. Require Claude Code 2.1.280 or later. Preserve configured effort levels; model selection does not set effort.
