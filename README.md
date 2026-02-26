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
- `docs/`: reference and source material
- `docs/project-preferences.md`: durable project maintenance preferences
