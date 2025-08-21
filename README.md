# Claude Code

Useful items for better usage of Claude Code.

## General Claude Code Tips

- always define `CLAUDE.md` file in root of each project.
- if using IDE (e.g. VS Code or Cursor), integrate Claude Code with IDE (https://docs.anthropic.com/en/docs/claude-code/ide-integrations).
- Claude Code is multi modal and good with images/screenshots of issues, etc.
- pick model deliberately to control usage and speed (using `/model`).
- using "ultra thinking mode" in your prompts is the easiest way to get longer reasoning.
- for large codebases, get Claude Code to build an index/map first.
- use `/resume` to resume a prior chat.
- use `@` to tell include specific files/directories.
- double tap `Esc` to jump back in chat.
- use `#` to add to memory without committing to repo.


## Directories

- `agents/`: take advantage of agent/subagent functionality.
- `commands/`: defining frequently used prompts.
- `container/`: container for safely running in YOLO mode.
- `hooks/`: WIP.

See README in each directory for more information.