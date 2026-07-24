---
description: Remove confirmed stale or temporary artifacts safely
---

# Cleanup

Resolve the exact cleanup scope before deleting anything.

1. Read repository instructions and inspect status, ignore rules, references, build paths, and recent changes.
2. Classify candidates as required, generated, temporary, stale, duplicate, or uncertain.
3. Delete only confirmed in-scope targets. Preserve unrelated work, user data, current dependencies, legal notices, and durable rationale.
4. Prefer recoverable deletion when practical. Never use unresolved variables, broad globs, a home directory, workspace root, or repository root as a recursive target.
5. Update references and ignore rules so one clear current path remains.
6. Run focused checks and inspect the final status.

If ownership or recovery is unclear, stop and ask. Report what was removed and whether it can be recovered.
