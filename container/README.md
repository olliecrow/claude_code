# Claude Code container

This directory builds and runs Claude Code in a Docker container for trusted projects.

## Authentication

The container accepts `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`, or a Linux `~/.claude/.credentials.json` file. A normal macOS login is stored in Keychain and is not visible inside Docker.

Subscription users can run `claude setup-token`, store the result securely, and export it as `CLAUDE_CODE_OAUTH_TOKEN`. Do not put tokens in this repository or pass them as script arguments.

## Build

```bash
./build.sh
./build.sh --minimal
```

The full image includes native build tools, Rust, Python data tools, ffmpeg, and debugging tools. The minimal image omits the optional compiler and debugger groups.

## Check and preview

```bash
./doctor.sh
./dry_run.sh /path/to/project
./dry_run.sh /path/to/project --shell
```

## Run

```bash
./run.sh /path/to/project
./run.sh /path/to/project --shell
./run_command.sh /path/to/project "your prompt"
./run_sequence_prompts.sh /path/to/project /path/to/prompts.txt
```

The prompt file format is:

- blank lines separate prompts;
- lines beginning with `#` are comments;
- a prompt beginning with `/compact` ends the current conversation;
- text after `/compact` becomes the first prompt in the new conversation.

Handoffs and logs are written to the target project’s ignored `plan/handoffs/` directory.

## Important security limits

The project and `~/.claude` are mounted read-write, the container has network access, and Claude runs with permission checks bypassed. Auth environment variables remain visible to local Docker inspection until the container is removed. Use only trusted projects and prompts. Git and GitHub CLI command names are blocked to prevent common accidental changes, but the block is not a security boundary.
