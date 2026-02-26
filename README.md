# claude_code

`claude_code` is a practical toolkit for Claude Code workflows.
It gives you container scripts, reusable agents, reusable commands, and automation helpers.

## What this project is trying to achieve

Make local agent workflows fast and repeatable.

## What you experience as a user

1. You build the runtime container once.
2. You run Claude Code against any local project path.
3. You reuse agents and commands from this repo in your own setup.
4. You run scripted sequences for repeatable multi-step workflows.

## Quick start

Build the container.

```bash
./container/build.sh
```

Run Claude Code against a project path.

```bash
./container/run.sh /path/to/project
```

Run a single prompt headlessly.

```bash
./container/run_command.sh /path/to/project "your prompt"
```

Run preflight checks before launching long sessions.

```bash
./container/doctor.sh
```

Preview the full run flow without starting Docker.

```bash
./container/dry_run.sh /path/to/project
./container/dry_run.sh /path/to/project --shell
```

## Example output

Doctor summary.

```text
claude_code container doctor
[ok] tool docker: /usr/local/bin/docker
[ok] host claude auth dir: $HOME/.claude
doctor result: PASS
```

Dry-run summary.

```text
claude_code container dry-run
repo: /path/to/project
mode: launch claude
planned sequence:
1. Validate local prerequisites.
2. Merge container settings.
3. Start detached container and mounts.
4. Launch Claude or shell.
5. Remove container and restore settings.
dry-run only: no Docker commands were executed.
```

## Requirements

- Docker
- shell environment with `bash`
- Claude Code CLI access, or a compatible local setup
- optional Node.js for external tools like `ccusage`

## Authentication

Container scripts reuse your local Claude authentication state.

- You can authenticate interactively on first run.
- You can use `ANTHROPIC_API_KEY` for API key based flows.

## Helpful tips

- Use `./container/run.sh /path/to/project --shell` for manual debugging inside the container.
- Check environment and auth state before long headless runs.

## Directory layout

- `container/`: build and run scripts, runtime utilities
- `agents/`: reusable agent definitions
- `commands/`: reusable slash commands
- `hooks/`: hook scripts for workflow orchestration
- `docs/`: reference docs snapshots and notes
- `plan/`: short lived planning and experiment notes

## Documentation map

- `README.md`: human-facing project overview
- `container/README.md`: container setup and runtime behavior
- `agents/README.md`: agent asset usage
- `commands/README.md`: command asset usage
- `docs/README.md`: docs index and routing
- `docs/project-preferences.md`: durable project maintenance preferences
