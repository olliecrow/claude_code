#!/usr/bin/env python3
"""
Claude Code Container Settings Merger

Merges user's existing Claude settings with container-specific permissions.
Preserves user hooks and other settings while only replacing the permissions section.
"""

import json
import os
import sys
from pathlib import Path


def merge_settings(user_settings_path, output_path):
    """
    Merge user's Claude settings with container permissions.

    Args:
        user_settings_path: Path to user's ~/.claude/settings.json
        output_path: Path where merged settings should be written
    """

    # Container-specific permissions that bypass restrictions
    container_permissions = {
        "defaultMode": "bypassPermissions",
        "allow": [
            "Bash",
            "Edit",
            "Glob",
            "Grep",
            "LS",
            "List",
            "MultiEdit",
            "NotebookEdit",
            "NotebookRead",
            "Read",
            "Task",
            "TodoWrite",
            "WebSearch",
            "Write",
        ],
        "deny": [
            "Bash(:*CLAUDE.md:*)",
            "Edit(*CLAUDE.md*)",
            "MultiEdit(*CLAUDE.md*)",
            "WriteFile(*CLAUDE.md)",
            "Write(*CLAUDE.md)",
            "Bash(git:*)",
        ],
        "additionalDirectories": [
            "/",
            "/workspace",
            "/home",
            "/etc",
            "/usr",
            "/var",
            "/tmp",
            "/root",
            "../",
        ],
    }

    try:
        # Read user's existing settings
        if os.path.exists(user_settings_path):
            with open(user_settings_path, "r") as f:
                user_settings = json.load(f)
        else:
            # Fallback to minimal settings if user has no settings file
            user_settings = {}

        # Preserve all user settings, only replace permissions
        merged_settings = user_settings.copy()
        merged_settings["permissions"] = container_permissions

        # Ensure output directory exists
        os.makedirs(os.path.dirname(output_path), exist_ok=True)

        # Write merged settings
        with open(output_path, "w") as f:
            json.dump(merged_settings, f, indent=2)

        print(
            f"Successfully merged settings from {user_settings_path} to {output_path}"
        )
        return True

    except json.JSONDecodeError as e:
        print(f"Error: Invalid JSON in user settings file: {e}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"Error merging settings: {e}", file=sys.stderr)
        return False


def main():
    if len(sys.argv) != 3:
        print("Usage: merge_settings.py <user_settings_path> <output_path>")
        print(
            "Example: merge_settings.py ~/.claude/settings.json /project/.claude/settings.json"
        )
        sys.exit(1)

    user_settings_path = sys.argv[1]
    output_path = sys.argv[2]

    success = merge_settings(user_settings_path, output_path)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
