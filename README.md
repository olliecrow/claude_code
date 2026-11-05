# Claude Code workflow toolkit

This repository contains a Docker runtime, reusable agents, slash commands, and a sequential prompt runner for Claude Code. Runtime launchers and agents use `claude-opus-5-5`; Claude Code 2.1.280 or later is required, and the image pins 2.1.311. Existing effort settings are preserved.

## Quick start

Requirements:

- Docker (rootful; rootless Docker maps the container user to a different uid)
- Bash
- authentication usable inside Docker

macOS stores an ordinary Claude Code login in Keychain, which a Linux container cannot read. For a Claude subscription, create a long-lived token and keep it in your shell’s secure environment:

```bash
claude setup-token
export CLAUDE_CODE_OAUTH_TOKEN=...
```

API users can instead set `ANTHROPIC_API_KEY`. When both are set, the launcher forwards only `CLAUDE_CODE_OAUTH_TOKEN`. Linux users with `~/.claude/.credentials.json` do not need either environment variable; the launcher copies only that one file into the run.

Build the image and check the local setup.

```bash
./container/build.sh
./container/doctor.sh
```

Preview a run without starting a container.

```bash
./container/dry_run.sh /path/to/project
```

Start Claude Code or an interactive shell.

```bash
./container/run.sh /path/to/project
./container/run.sh /path/to/project --shell
```

Run one non-interactive prompt.

```bash
./container/run_command.sh /path/to/project "run the tests and explain any failures"
```

Run prompts from a file. Separate prompts with blank lines. A `/compact` block starts a fresh conversation with a generated handoff.

```bash
./container/run_sequence_prompts.sh /path/to/project /path/to/prompts.txt
```

## Security boundary

Use the container only with projects and prompts you trust.

- The project is mounted read-write; review changed project files before running them on the host. The top-level `.git` (directory or worktree file) is mounted read-only, so Claude cannot commit, and the launchers never run host Git.
- Residual risk: the container can still write submodule `.git` files and nested Git metadata, or create Git metadata in a project with no `.git`, and host Git runs commands named there; until you have reviewed a run's changes, run host Git only from the project root with `--ignore-submodules=all`, and not at all in a project that had no `.git`.
- Claude's config is a new temporary directory for each run. Host sessions, history, settings, plugins, and MCP config are not visible. Set `CLAUDE_CONTAINER_MOUNT_HOST_CONFIG=1` to mount host skills, agents, commands, settings, and plugins from `~/.claude` read-write; user MCP servers in `~/.claude.json` and host session resume do not carry over.
- The container runs as your host uid with all Linux capabilities dropped and `no-new-privileges` set.
- The container has internet access.
- Claude runs with permission checks bypassed.
- Only the auth variable in use is forwarded. It is visible to local Docker inspection while the container runs.
- Common Git commands are blocked, but this is a guardrail rather than a complete security boundary.

The container limits ordinary filesystem access to its own filesystem and the mounted paths. It does not protect the run's credentials or project data from code or commands run inside it. Deny rules for the credentials file stop Claude's file tools, not every indirect read through Bash.

## Reusable assets

- Copy files from `agents/` to `~/.claude/agents/`.
- Copy files from `commands/` to `~/.claude/commands/`.

See [agents/README.md](agents/README.md) and [commands/README.md](commands/README.md).

## Repository layout

- `container/`: image and runtime scripts
- `agents/`: Claude Code subagent definitions
- `commands/`: Claude Code slash commands
- `docs/`: durable project decisions
- `scripts/`: repository checks and public-safety checks

Generated handoffs and transcripts go to `plan/handoffs/` in the target project. The sequence runner adds a `.gitignore` there, so Git ignores them.

## Development

Run the local gate before committing.

```bash
./scripts/check.sh
pre-commit run --all-files
```

Security reports belong in [SECURITY.md](SECURITY.md). The project is licensed under [Apache License 2.0](LICENSE).
