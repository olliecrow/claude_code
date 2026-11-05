# Claude Code agents

These files are standalone Claude Code subagent definitions.

## Install

Copy the agents you want into `~/.claude/agents/`. A running session picks up the files when that directory already existed; restart Claude Code if you just created it.

```bash
cp agents/code-reviewer.md ~/.claude/agents/
```

Each agent has one narrow role. The prompts keep planning and validation proportional, preserve the caller’s authority boundary, and avoid routine delegation.

The strictly read-only agents (`code-reviewer`, `documentation-finder`, `large-file-reader`, `online-researcher`) set `disallowedTools: Edit, Write, NotebookEdit`. They keep `Bash`, because on macOS and Linux Claude Code searches files through `Bash`, so Bash can still change files. `permissionMode` is not set: Claude Code ignores it when the main session uses bypass, auto, or accept-edits mode.

See the official [Claude Code subagent documentation](https://code.claude.com/docs/en/sub-agents) for file format and configuration details.
