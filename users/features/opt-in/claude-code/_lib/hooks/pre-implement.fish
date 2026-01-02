#!/usr/bin/env fish
# ~/.claude/hooks/pre-implement.fish
# Pre-implementation hook for ACE system - loads memory and relevant strategies
# Uses semantic embeddings for strategy retrieval

# Hook receives JSON via stdin:
# {
#   "tool_name": "Edit|Write",
#   "tool_input": {"file_path": "...", ...},
#   "session_id": "...",
#   "cwd": "..."
# }

# Read hook input from stdin
set -l hook_data (cat)

# Extract fields
set -l file_path (echo $hook_data | jq -r '.tool_input.file_path // ""')
set -l session_id (echo $hook_data | jq -r '.session_id // "unknown"')
set -l cwd (echo $hook_data | jq -r '.cwd // ""')

# Skip if no file path
if test -z "$file_path"
    exit 0
end

# Ensure session directory exists
mkdir -p "$HOME/.claude/ace-sessions"

# Check if we already initialized this session
set -l init_marker "$HOME/.claude/ace-sessions/.init-$session_id"
if not test -f $init_marker
    # First Edit/Write of session - check for project memory
    if test -d "$cwd/.agent-memory"
        echo "ACE: Project memory detected. Run '/memory-read' to load context."
    end
    touch $init_marker
end

# Check if we already loaded strategies for this session
set -l strategy_marker "$HOME/.claude/ace-sessions/.strategies-$session_id"
if test -f $strategy_marker
    exit 0
end

# Build task context from file path
set -l ext (string match -r '\.[^.]+$' $file_path | string sub -s 2)
set -l filename (basename $file_path)
set -l dirname (dirname $file_path)

# Create semantic context description
set -l task_context "implementing"

switch $ext
    case ts tsx js jsx
        set task_context "$task_context typescript javascript frontend code"
    case py
        set task_context "$task_context python code"
    case rs
        set task_context "$task_context rust systems code"
    case nix
        set task_context "$task_context nix nixos configuration"
    case fish sh bash
        set task_context "$task_context shell script"
    case md
        set task_context "$task_context documentation markdown"
    case go
        set task_context "$task_context go golang code"
    case '*'
        set task_context "$task_context code"
end

# Add path-based context hints
if string match -q '*auth*' $file_path
    set task_context "$task_context authentication security"
end
if string match -q '*secret*' $file_path; or string match -q '*password*' $file_path; or string match -q '*cred*' $file_path
    set task_context "$task_context security secrets credentials"
end
if string match -q '*test*' $file_path; or string match -q '*spec*' $file_path
    set task_context "$task_context testing tests"
end
if string match -q '*api*' $file_path; or string match -q '*route*' $file_path; or string match -q '*handler*' $file_path
    set task_context "$task_context api endpoint error handling"
end
if string match -q '*util*' $file_path; or string match -q '*helper*' $file_path; or string match -q '*common*' $file_path
    set task_context "$task_context refactoring shared utilities"
end
if string match -q '*debug*' $file_path; or string match -q '*fix*' $file_path
    set task_context "$task_context debugging bug fix"
end

set task_context "$task_context in $filename"

# Query embeddings for relevant strategies
set -l ace_script "$HOME/.claude/scripts/ace-embeddings.py"

if test -x $ace_script
    # Use semantic search
    set -l results ($ace_script query "$task_context" 3 2>/dev/null)

    if test -n "$results"
        set -l strategies (echo $results | jq -r '.[] | select(.similarity > 0.15) | "  • \(.name) (\(.similarity | tostring | .[0:5]))"')

        if test -n "$strategies"
            echo "ACE: Relevant strategies (semantic):"
            echo $strategies
            echo ""
        end
    end
else
    # Fallback to keyword matching if embeddings not available
    set -l relevant_strategies "Baby Steps Implementation"

    if string match -q '*security*' $task_context
        set -a relevant_strategies "Security First Strategy"
    end
    if string match -q '*error*' $task_context; or string match -q '*api*' $task_context
        set -a relevant_strategies "Error Handling Strategy"
    end
    if string match -q '*test*' $task_context
        set -a relevant_strategies "Test Writing Strategy"
    end

    if test (count $relevant_strategies) -gt 1
        echo "ACE: Relevant strategies (keyword):"
        for strat in $relevant_strategies
            echo "  - $strat"
        end
        echo ""
    end
end

# Mark that we've shown strategies for this session
mkdir -p (dirname $strategy_marker)
touch $strategy_marker

exit 0
