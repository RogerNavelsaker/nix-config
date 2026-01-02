#!/usr/bin/env fish
# ~/.claude/hooks/weekly-curation.fish
# Weekly curation trigger for ACE system

# Run via cron or systemd timer:
# 0 9 * * 0 ~/.claude/hooks/weekly-curation.fish

# Count unprocessed reflections in main project
# Using list_directory to count files in reflections folder
set -l reflection_count (uvx basic-memory tool list-directory --dir-name /reflections --project main 2>/dev/null | grep -c "\.md" 2>/dev/null || echo 0)
# Ensure we have a single integer
set reflection_count (string trim -- $reflection_count | head -1)

echo "ACE Weekly Curation Check"
echo "========================="
echo "Pending reflections: $reflection_count"

if test "$reflection_count" -ge 5
    echo "Recommendation: Run '/ace curate' to update playbook"
    # Send desktop notification if available
    if command -v notify-send &>/dev/null
        notify-send "ACE Curation" "You have $reflection_count pending reflections. Consider running /ace curate"
    end
else
    echo "Status: Playbook up to date"
end
