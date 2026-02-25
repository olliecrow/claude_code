# claude_code

`claude_code` is a practical toolkit for running Claude Code and Codex-oriented workflows with reusable agents, commands, container runtimes, and automation helpers.

## Project Aim

Make local agent workflows repeatable and fast by packaging:

- containerized runtime scripts
- reusable agent/command definitions
- automation hooks and sequence runners
- reference documentation snapshots

## What This Repository Does

- provides hardened container scripts in `container/`
- includes reusable agent and slash-command assets (`agents/`, `commands/`)
- includes workflow hooks (`hooks/`) and sequence scripts
- tracks supporting docs and research notes (`docs/`, `plan/`)

## Requirements

- Docker
- shell environment with `bash`
- Claude Code CLI access (or compatible local setup)
- optional: Node.js for external usage tools such as `ccusage`

## Authentication

Container scripts can reuse local Claude authentication state. Depending on your setup:

- you may authenticate interactively on first run
- or provide `ANTHROPIC_API_KEY` when using API-key-based flows

## Quick Start

Build the container:

```bash
./container/build.sh
```

Launch Claude Code against a project:

```bash
./container/run.sh /path/to/project
```

Run a single prompt headlessly:

```bash
./container/run_command.sh /path/to/project "your prompt"
```

## Getting Started

1. Build the container image.
2. Run against a target project path.
3. Copy selected agents/commands into your local Claude config if needed.
4. Use sequence runners for multi-prompt workflows.

## Local State and Directory Layout

- `container/`: build + run scripts and container runtime utilities
- `agents/`: reusable agent definitions
- `commands/`: reusable slash commands
- `hooks/`: hook scripts for workflow orchestration
- `docs/`: reference docs snapshots and notes
- `plan/`: short-lived planning and experiment notes

## Logging and Debugging

- runtime logs stream to terminal from `container/run*.sh`
- use `./container/run.sh /path/to/project --shell` for manual debugging inside container
- verify environment/auth state before long headless runs

## Documentation Map

- `README.md`: human-facing project overview
- `container/README.md`: container setup and runtime behavior
- `agents/README.md`: agent asset usage
- `commands/README.md`: command asset usage
- `docs/`: reference/source material used by this repo
- `docs/project-preferences.md`: durable project maintenance preferences
