# Claude Code Container

Docker runtime tuned for Claude Code with host isolation. Defaults to the Opus model and runs with `--dangerously-skip-permissions`.

## Highlights
- Security layers block Git (APT pin + wrapper) and confine caches to `/tmp`.
- Tooling bundle includes ripgrep, ffmpeg, sccache, Node.js, Rust, and build essentials.
- ML stack ships OpenCV, matplotlib, data-science libs, optional minimal build via `--minimal`.

## Build
```
./build.sh            # full image
./build.sh --minimal  # lean image
# or
docker build --pull --no-cache -t claude_code_container .
```

## Run
```
./run.sh /path/to/project                     # launch Claude automatically
./run.sh /path/to/project --shell             # obtain a shell
./run_command.sh /path/to/project "prompt"    # execute one prompt
./run_sequence_incontext.sh /path/to/project "seed"
./run_sequence_handoff.sh /path/to/project "seed"
./run_sequence_prompts.sh /path/to/project /path/to/prompts.txt
```
First launch may prompt for login; later runs reuse the stored session.

## Prompt Sequences
- `run_sequence_prompts.sh` reads prompts separated by blank lines.
- `/compact` triggers a handoff to a fresh conversation.
- Lines starting with `#` act as comments.

## Alias Tip
```
alias ccc="/path_to_repo/container/run.sh"
ccc .
```

## API Key Notes
- Claude Code usually reuses `~/.claude`; no explicit key needed.
- Generate keys via https://console.anthropic.com/ when required.
- On macOS: `security find-generic-password -s "Claude Code" -a "$USER" -w`.
- Optional env export before launch: `export ANTHROPIC_API_KEY=...`.
