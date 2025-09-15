# Claude Code Container

Docker environment for running Claude Code with host isolation.

NOTE: container will always use sonnet (`--model=sonnet`) for usage management - model can be adjusted within a chat with `/model`.

WARNING: uses `dangerously-skip-permissions` mode (i.e. YOLO mode).

## Features

- **Enhanced Security**: Multiple layers of Git blocking (APT pinning + wrapper scripts)
- **Developer Tools**: ripgrep, ffmpeg, sccache for productivity
- **ML/Graphics Support**: Libraries for OpenCV, matplotlib, and data science workflows
- **Build Flexibility**: Optional build tools via `--minimal` flag
- **Rust & Node.js**: Full toolchain support for modern development
- **Temporary Caching**: All package caches isolated to `/tmp` for security

## Quick Start

```bash
# Build full container with all tools (default)
./build.sh

# Build minimal container without extra build tools
./build.sh --minimal

# Build container from scratch (alternative to build.sh)
docker build --pull --no-cache -t claude_code_container .

# Run with your project directory (Claude starts automatically)
./run.sh /path/to/your/project

# Or get a shell in the container
./run.sh /path/to/your/project --shell

# Or run a single command in the container, then exit
./run_command.sh /path/to/your/project "this is my prompt, which will execute in the container"

# Or run a sequence of commands in the container (in context), then exit
./run_sequence_incontext.sh /path/to/your/project "this is my seed prompt"

# Or run a sequence of commands in the container (with rollup handoffs), then exit
./run_sequence_handoff.sh /path/to/your/project "this is my seed prompt"
```

Note: The first time running `run.sh`, you may have to login to Claude Code. This should only occur once. All subsequent uses of `run.sh` should not require you to log into Claude Code.

## Useful Tip

Creating an alias to the `run.sh` is helpful.

Like this:

```
alias ccc="/path_to_repos/claude_code_container/container/run.sh"
```

Then you can be in any directory, and run:

```
ccc .
```

## Anthropic API Key

By default, Claude Code will pick up your usual setup (~/.claude).

So ignore this section, unless you want to use an API key explicitly (special case).

Explicitly setting your `ANTHROPIC_API_KEY` is not neccessary in most cases.

### Get Anthropic API Key (from Console)

New key can be generated via Anthropic console: https://console.anthropic.com/

### Get Anthropic API Key (from Mac)

If you're already using Claude Code on Mac, type this to get your existing API key:

```bash
security find-generic-password -s "Claude Code" -a "$USER" -w
```

### Set Anthropic API Key

On host machine, prior to launching container:

```
export ANTHROPIC_API_KEY=your_api_key_here
```