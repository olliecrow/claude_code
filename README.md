# Claude Code

Toolkit for running Claude Code and Codex CLI with ready-made agents, commands, containers, hooks, and research notes.

## Structure
- `agents/` Ready-to-copy subagents; see `agents/README.md`.
- `commands/` Slash commands that pair with the agents; see `commands/README.md`.
- `container/` Hardened Claude Code container with helper scripts (`run.sh`, `run_command.sh`, `run_sequence_*`).
- `codex_container_example/` Minimal Codex CLI container for autonomous runs.
- `hooks/` Automation hooks such as `multiworkflow.py` for staged `/plan` flows.
- `plan/` Backlog, experiments, permission research, and run artifacts.
- `.claude/` Workspace for hook state during local runs.
- `update_from_personal.sh` Sync script for pulling local Claude assets into the repo.

## Start Here
- Build or run the container from `container/README.md`.
- Copy selected agents into `~/.claude/agents/` and commands into `~/.claude/commands/`.
- Drop `hooks/multiworkflow.py` into `~/.claude/hooks/` if automated planning is needed.
- Launch Claude Code or Codex CLI, then use `/agents` and `/` to verify install.

## Usage Notes
- Create `CLAUDE.md` in each project root.
- Integrate with an IDE via Anthropic’s docs if desired.
- Use `/model` to switch models and `/resume` to pick up past chats.
- Request indexes for large repos, target files with `@`, and stash notes with `#`.
- Double-tap `Esc` to return focus to the chat pane.

## Monitor Usage
- Historical: https://github.com/ryoppippi/ccusage
- Realtime: https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor

## Planning and Research
- `plan/comprehensive_solution.md` outlines the permission bypass strategy.
- `plan/run_command_analysis.md` and `plan/run_scripts_consistency_check.md` cover command behaviour studies.
- `plan/backlog`, `plan/current`, `plan/complete`, `plan/experiments`, `plan/research`, `plan/scratch`, and `plan/artifacts/` keep ongoing work organised.

## Handy Aliases
```
alias ccc="{path_to_repo}/container/run.sh"
alias ccs="{path_to_repo}/container/run_sequence_handoff.sh"
alias ccu="npx --yes ccusage@latest"
alias ccm="claude-monitor"
```
