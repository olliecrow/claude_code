# Claude Code Commands

Claude Code offers support for defining frequently used prompts (a.k.a custom slash commands).

## Setup

Copy command markdown files into: `~/.claude/commands/`

## Verify Correct Setup

Once inside of Claude Code, type `/` and you should see a list of all custom slash commands.

```
claude .
/
```

## Usage

There is no implicit selection/usage of custom slash commands by Claude Code.

You need to explicitly call custom slash commands.

Once inside of Claude Code, type `/` and you should see all custom commands.

e.g. `/plan run all of the unit tests across my project. investigate and fix any failing tests.`

## Tip

Generally, it's good to rely on custom commands to call agents (see `/agents` directory in this repo).

Most powerful command defined in this project is `/plan`.

Calling the same custom slash command for multiple consequetive prompts is helpful to keep Claude Code on track.

e.g.

```
/plan ...
/plan ...
/plan ...
```

Highly recommended to only run Claude Code inside of a container (see `/container` directory in this repo).

Use frontmatter to constrain usage: https://docs.anthropic.com/en/docs/claude-code/slash-commands#frontmatter

## Documentation

https://docs.anthropic.com/en/docs/claude-code/slash-commands