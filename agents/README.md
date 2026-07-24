# Claude Code agents

These files are standalone Claude Code subagent definitions.

## Install

Copy the agents you want into `~/.claude/agents/`, then run `/agents` in Claude Code to confirm they are available.

```bash
cp agents/code-reviewer.md ~/.claude/agents/
```

Each agent has one narrow role. The prompts keep planning and validation proportional, preserve the caller’s authority boundary, and avoid routine delegation.

See the official [Claude Code subagent documentation](https://docs.anthropic.com/en/docs/claude-code/sub-agents) for file format and configuration details.
