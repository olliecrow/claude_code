#!/bin/bash
# Shared library for Claude Code container settings management

# Function to setup container settings by merging user settings with container permissions
setup_container_settings() {
    local repo_dir="$1"
    local settings_dir="$repo_dir/.claude"
    local settings_file="$settings_dir/settings.json"
    local backup_file="$settings_dir/settings.json.backup"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    mkdir -p "$settings_dir"
    
    # Backup existing settings.json if it exists
    if [ -f "$settings_file" ]; then
        cp "$settings_file" "$backup_file"
        echo "Backed up existing settings.json to settings.json.backup"
    else
        # Remove any stale backup if no original exists
        if [ -f "$backup_file" ]; then
            rm -f "$backup_file"
        fi
    fi
    
    # Use Python helper to merge user settings with container permissions
    if ! python3 "$script_dir/merge_settings.py" "$HOME/.claude/settings.json" "$settings_file"; then
        echo "Error: Failed to merge settings. Falling back to basic container settings."
        # Fallback to basic settings if merge fails
        cat > "$settings_file" << 'EOF'
{
  "permissions": {
    "defaultMode": "bypassPermissions",
    "allow": [
      "Bash(*)", "Edit(*)", "Glob(*)", "Grep(*)", "LS(*)", "List(*)", "List(..)",
      "MultiEdit(*)", "NotebookEdit(*)", "NotebookRead(*)", "Read(*)", "Task(*)",
      "TodoWrite(*)", "WebFetch(*)", "WebSearch(*)", "Write(*)"
    ],
    "deny": [
      "Bash(*CLAUDE.md*)", "Edit(*CLAUDE.md*)", "MultiEdit(*CLAUDE.md*)",
      "WriteFile(*CLAUDE.md)", "Write(*CLAUDE.md)", "Bash(git*)"
    ],
    "additionalDirectories": ["/", "/workspace", "/home", "/etc", "/usr", "/var", "/tmp", "/root", "../"]
  }
}
EOF
    fi
    
    # Export paths for cleanup function
    export SETTINGS_FILE="$settings_file"
    export BACKUP_FILE="$backup_file"
}

# Function to restore backup on exit or crash
restore_settings_json() {
    if [ -f "$BACKUP_FILE" ]; then
        mv -f "$BACKUP_FILE" "$SETTINGS_FILE"
        echo "Restored original settings.json from backup."
    else
        rm -f "$SETTINGS_FILE"
        echo "Removed settings.json (no backup existed)."
    fi
}