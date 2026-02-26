# Project Preferences (Going Forward)

These preferences define how `claude_code` should be maintained as an open-source-ready workflow toolkit.

## Quality and Scope

- Keep agents/commands/hooks modular and understandable.
- Keep runtime/container behavior explicit and easy to reproduce.
- Prefer small, high-confidence changes over broad speculative edits.

## Security and Confidentiality

- Never commit secrets, credentials, tokens, API keys, or private key material.
- Never commit private/sensitive machine paths; use placeholders such as `/path/to/project`, `/Users/YOU`, `/home/user`, or `C:\\Users\\USERNAME`.
- Keep local runtime state untracked (`.env*`, `.claude/`, `.codex/`, temp artifacts).
- If sensitive data is found in history, rotate credentials and scrub history before publication.

## Documentation Expectations

- Keep `README.md`, asset READMEs, and `docs/` aligned with real behavior.
- Keep examples safe to publish (no private values, no local-only assumptions without callouts).

## Verification Expectations

- Run relevant checks for changed scripts/docs/assets before merge.
- For container runtime changes, run `./container/doctor.sh` and relevant `./container/dry_run.sh` previews before merge.
- Include concise verification evidence in PR descriptions when practical.

## Collaboration Preferences

- Preserve accurate author/committer attribution for each contributor.
- Prefer commit author identities tied to genuine human GitHub accounts, not fabricated bot names/emails.
- Avoid destructive history rewrites unless required for secret/confidentiality remediation.
