# Claude Code container

This directory builds and runs Claude Code in a Docker container for trusted projects.

## Authentication

The container accepts `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_API_KEY`, or a Linux `~/.claude/.credentials.json` file. When neither variable is set, the launcher copies only that credentials file into a temporary config directory for the run. A normal macOS login is stored in Keychain and is not visible inside Docker.

Subscription users can run `claude setup-token`, store the result securely, and export it as `CLAUDE_CODE_OAUTH_TOKEN`. Do not put tokens in this repository or pass them as script arguments.

## Build

```bash
./build.sh
./build.sh --minimal
./build.sh --no-cache
```

Both images contain Claude Code 2.1.311, uv, Python 3.12, and ripgrep. The full image adds native build tools, debuggers, Node.js 22, Rust, ffmpeg, and Python data tools (Jupyter, NumPy, pandas, and others) on `PATH`. The minimal image has none of those.

Every download is pinned by version and SHA-256 checksum in the `Dockerfile`. To move a version, change the version and its checksums together. Builds use the Docker cache; pass `--no-cache` to refresh Debian packages.

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

`run_command.sh` and each turn of `run_sequence_prompts.sh` stop after `CLAUDE_TIMEOUT_SECONDS` (default 5400). A turn that times out or returns an error result stops the sequence and marks it `FAILED`.

The prompt file format is:

- blank lines separate prompts;
- lines beginning with `#` are comments;
- a prompt beginning with `/compact` ends the current conversation;
- text after `/compact` becomes the first prompt in the new conversation.

Handoffs and logs are written to the target project’s `plan/handoffs/` directory. Add `plan/` to that project's `.gitignore`; the runner warns when it is not ignored.

Each run uses a new temporary home at `/home/dev` and deletes it afterwards, so sessions do not carry over between runs. To use your host config (skills, MCP servers, history, resume), set `CLAUDE_CONTAINER_MOUNT_HOST_CONFIG=1`. That mounts `~/.claude` read-write.

`run.sh --shell` runs with all capabilities dropped, so `gdb` and `valgrind` may not be able to trace processes. Rebuild the image after you update this repository; the launch scripts expect the current image layout.

## Important security limits

The project is mounted read-write, the container has network access, and Claude runs with permission checks bypassed. The container runs as your host uid with all Linux capabilities dropped. Auth environment variables remain visible to local Docker inspection until the container is removed. Use only trusted projects and prompts. Git and GitHub CLI command names are blocked to prevent common accidental changes, but the block is not a security boundary.
