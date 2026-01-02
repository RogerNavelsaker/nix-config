#!/usr/bin/env fish
# ~/.claude/hooks/post-task.fish
# Post-task hook for ACE system - logs file changes for reflection

# Hook receives JSON via stdin:
# {
#   "tool_name": "Edit|Write",
#   "tool_input": {"file_path": "...", ...},
#   "tool_response": {"success": true, ...},
#   "session_id": "...",
#   "cwd": "..."
# }

# Read hook input from stdin
set -l hook_data (cat)

# Extract fields using jq
set -l tool_name (echo $hook_data | jq -r '.tool_name // "unknown"')
set -l file_path (echo $hook_data | jq -r '.tool_input.file_path // "unknown"')
set -l session_id (echo $hook_data | jq -r '.session_id // "unknown"')
set -l timestamp (date -Iseconds)

# Session log file (daily rotation)
set -l log_date (date +%Y-%m-%d)
set -l session_log "$HOME/.claude/ace-sessions/$log_date.jsonl"

# Ensure directory exists
mkdir -p (dirname $session_log)

# Append to session log (JSONL format)
echo "{\"timestamp\":\"$timestamp\",\"tool\":\"$tool_name\",\"file\":\"$file_path\",\"session\":\"$session_id\"}" >> $session_log

# Count changes in current session
set -l change_count (grep -c "\"session\":\"$session_id\"" $session_log 2>/dev/null || echo 0)

# After 10+ changes, suggest reflection (output goes to Claude's context)
if test "$change_count" -ge 10
    # Check if we already suggested for this session
    set -l suggestion_marker "$HOME/.claude/ace-sessions/.suggested-$session_id"
    if not test -f $suggestion_marker
        echo "ACE: Session has $change_count file changes. Consider running '/ace reflect' when complete."
        touch $suggestion_marker
    end
end

exit 0
