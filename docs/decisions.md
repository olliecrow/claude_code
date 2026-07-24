# Project decisions

## Plain English and clear names

The project uses short, direct language and descriptive names in prompts, docs, code, and maintenance work. This keeps reusable instructions easy to understand and reduces unsafe guesses when scripts are changed.

Enforcement lives in `AGENTS.md`.

## Container trust boundary

The container is a convenient isolated runtime for trusted work, not a strong sandbox for untrusted code.

Claude needs network access, project write access, and authentication state for the workflows this repository supports. The launch scripts therefore mount the project and `~/.claude` read-write and bypass Claude permission prompts. On macOS, container authentication must be supplied separately because Docker cannot read the host Keychain. Blocking common Git commands reduces accidental repository operations but cannot stop arbitrary code from reading mounted data or downloading another Git client.

The README must state this boundary plainly. Do not describe the runtime as secure against malicious projects or prompts.

## Current model aliases

Runtime scripts use Claude Code’s `sonnet` alias instead of a dated model ID. The alias keeps the chosen model family while allowing the installed Claude Code release to resolve the current supported version.
