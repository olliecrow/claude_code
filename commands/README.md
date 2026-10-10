# Claude Code commands

These files are reusable Claude Code slash commands.

## Install

Copy the commands you want into `~/.claude/commands/`, then type `/` in Claude Code to confirm they are available.

```bash
cp commands/plan-mode.md ~/.claude/commands/
```

The commands separate planning, read-only inspection, testing, verification, cleanup, and implementation so the requested authority stays clear.

The planning and verification commands are named `plan-mode` and `verify-mode` so they never shadow Claude Code's built-in `/plan` command or its bundled `/verify` skill, and so they coexist with same-named skills from a personal skill catalogue.

See the official [Claude Code slash-command documentation](https://docs.anthropic.com/en/docs/claude-code/slash-commands) for file format and configuration details.
