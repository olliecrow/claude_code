# Claude Code Agents

Subagent definitions packaged for Claude Code.

## Install
- Copy markdown files into `~/.claude/agents/`.
- Run `/agents` inside Claude Code to confirm availability.

## Use
- Mention agent names in prompts or wire them through custom commands.
- Combine with slash commands from `../commands` for repeatable workflows.
- Separate context windows per agent; avoid nesting identical agents.
- Prefer container execution from `../container` for isolation.
- Apply frontmatter headers to constrain behaviour: https://docs.anthropic.com/en/docs/claude-code/sub-agents#file-format

## Reference
https://docs.anthropic.com/en/docs/claude-code/sub-agents
