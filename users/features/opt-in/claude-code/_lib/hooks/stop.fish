#!/usr/bin/env fish
# ~/.claude/hooks/stop.fish
# Stop hook for ACE system - prompts for memory update and git commit

# Hook receives JSON via stdin:
# {
#   "session_id": "...",
#   "cwd": "...",
#   "stop_reason": "user|end_turn|max_turns"
# }

# Read hook input from stdin
set -l hook_data (cat)

# Extract fields
set -l session_id (echo $hook_data | jq -r '.session_id // "unknown"')
set -l cwd (echo $hook_data | jq -r '.cwd // ""')

# Count changes made this session
set -l log_date (date +%Y-%m-%d)
set -l session_log "$HOME/.claude/ace-sessions/$log_date.jsonl"
set -l change_count 0

if test -f $session_log
    set change_count (grep -c "\"session\":\"$session_id\"" $session_log 2>/dev/null || echo 0)
    set change_count (string trim -- $change_count | head -1)
end

# Skip if no changes this session
if test "$change_count" -eq 0
    exit 0
end

set -l suggestions

# Check for uncommitted .agent-memory changes
if test -d "$cwd/.agent-memory"
    set -l uncommitted (git -C "$cwd" status --porcelain .agent-memory 2>/dev/null | wc -l | string trim)
    if test "$uncommitted" -gt 0
        set -a suggestions "Uncommitted memory files in .agent-memory/ - consider: git add .agent-memory && git commit"
    end
end

# Suggest memory update if significant changes
if test "$change_count" -ge 3
    set -a suggestions "Session had $change_count file changes - consider: /memory-update '<summary>'"
end

# Output suggestions
if test (count $suggestions) -gt 0
    echo ""
    echo "ACE Session Summary:"
    for s in $suggestions
        echo "  → $s"
    end
end

exit 0
