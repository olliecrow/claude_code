# Claude Code workflow toolkit

This repository contains a Docker runtime, reusable agents, slash commands, and a sequential prompt runner for Claude Code.

## Quick start

Requirements:

- Docker
- Bash
- Claude Code configuration in `~/.claude`
- authentication usable inside Docker

macOS stores an ordinary Claude Code login in Keychain, which a Linux container cannot read. For a Claude subscription, create a long-lived token and keep it in your shell’s secure environment:

```bash
claude setup-token
export CLAUDE_CODE_OAUTH_TOKEN=...
```

API users can instead set `ANTHROPIC_API_KEY`. Linux users with `~/.claude/.credentials.json` do not need either environment variable.

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

- The project and `~/.claude` are mounted read-write.
- The container has internet access.
- Claude runs with permission checks bypassed.
- Auth environment variables are visible to local Docker inspection while the container runs.
- Common Git commands are blocked, but this is a guardrail rather than a complete security boundary.

The container limits ordinary filesystem access to its own filesystem and the mounted paths. It does not protect mounted credentials or project data from code or commands run inside it.

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

Generated handoffs use the ignored `plan/handoffs/` directory in the target project.

## Development

Run the local gate before committing.

```bash
./scripts/check.sh
pre-commit run --all-files
```

Security reports belong in [SECURITY.md](SECURITY.md). The project is licensed under [Apache License 2.0](LICENSE).
