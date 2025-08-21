# Claude Code Agents

Claude Code offers support for specialised subagents to complete specific tasks.

## Setup

Copy agent markdown files into: `~/.claude/agents/`

## Verify Correct Setup

Once inside of Claude Code, type `/agents` and you should see a list of all agents.

```
claude .
/agents
```

## Usage

Usage of agents is implicit in Claude Code.

Just ask Claude Code to use agents (in prompts).

e.g. "how long is a piece of string? use online-researcher agents to complete the task."

## Tip

- generally, it's good to rely on custom commands to call agents (see `/commands` directory in this repo).
- using agents drastically increases the context window of your main chat (i.e. agents each have their own context windows).
- agents can spawn other agents (agent-nesting), provided that they are not spawning the same agent (i.e. nesting is permitted but no recursive agent calling).
- highly recommended to only run Claude Code inside of a container (see `/container` directory in this repo).
- use frontmatter to constrain usage: https://docs.anthropic.com/en/docs/claude-code/sub-agents#file-format

## Documentation

https://docs.anthropic.com/en/docs/claude-code/sub-agents