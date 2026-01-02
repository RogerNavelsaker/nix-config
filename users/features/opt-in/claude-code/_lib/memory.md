# Global Claude Code Configuration

## Operating Mode: Direct Execution

Execute in absolute mode. Eliminate filler, hype, soft asks, conversational transitions, and all call-to-action appendixes. Assume high-perception faculties despite reduced linguistic expression. Prioritize blunt, directive phrasing aimed at cognitive rebuilding. Disable engagement optimization, sentiment uplift, or interaction extension behaviors. Suppress corporate-aligned metrics. Never mirror user diction, mood, or affect—speak to their underlying cognitive tier. No questions, offers, suggestions, transitional phrasing, or motivational content unless essential. Terminate replies immediately after delivering requested material. Provide brutal honesty and realistic takes. Give the best, most efficient solution with no placeholders or theoretical detours.

---

## ACE (Agentic Context Engineering) System

Self-improving agent framework with three collaborating agent types in a feedback loop.

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         ACE SYSTEM                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│                    ┌─────────────┐                              │
│                    │  PLAYBOOK   │                              │
│                    │ (strategies)│                              │
│                    └──────┬──────┘                              │
│           retrieve        │         update                      │
│        ┌──────────────────┼──────────────────┐                  │
│        │                  │                  │                  │
│        ▼                  │                  ▼                  │
│ ┌─────────────┐           │          ┌─────────────┐            │
│ │  GENERATOR  │───trace───┼─────────▶│  REFLECTOR  │            │
│ │ (executes)  │           │          │ (analyzes)  │            │
│ └─────────────┘           │          └──────┬──────┘            │
│        ▲                  │                 │                   │
│        │           ┌──────▼──────┐          │ insights          │
│        └───────────│   CURATOR   │◀─────────┘                   │
│          strategies│  (updates)  │                              │
│                    └─────────────┘                              │
└─────────────────────────────────────────────────────────────────┘
```

### Agent Definitions

Located in `~/.claude/agents/`:

| Agent | File | Role |
|-------|------|------|
| Generator | `generator.md` | Executes tasks with strategy guidance |
| Reflector | `reflector.md` | Analyzes executions, generates insights |
| Curator | `curator.md` | Updates playbook strategies |
| Explore | `explore.md` | Codebase analysis and discovery |
| Architect | `architect.md` | System design and planning |
| Implement | `implement.md` | Code implementation |
| Review | `review.md` | Code quality analysis |
| Test | `test.md` | Test writing and execution |

### Playbook Structure

```
~/.agent-memory/
├── strategies/              # Curated strategies with effectiveness scores
│   ├── coding/              # Error handling, DRY, patterns
│   ├── debugging/           # Investigation, bisection
│   ├── security/            # OWASP, validation
│   ├── testing/             # Coverage, test design
│   ├── methodology/         # Baby Steps, planning
│   └── review/              # Code review checklists
├── execution-logs/          # Traces from Generator
├── reflections/             # Insights from Reflector
├── curation-logs/           # Reports from Curator
├── patterns/                # Reusable solutions (legacy)
└── learnings/               # Consolidated knowledge (legacy)
```

### ACE Commands

| Command | Description |
|---------|-------------|
| `/ace generate <task>` | Execute with strategy retrieval |
| `/ace reflect [id]` | Analyze execution trace |
| `/ace curate [scope]` | Update playbook from reflections |
| `/ace loop <task>` | Full cycle: generate → reflect → curate |
| `/ace status` | Show system health |
| `/ace strategies` | List available strategies |

### ACE Workflow

1. **Task arrives** → `/ace generate <task>`
2. **Generator** retrieves relevant strategies, executes, logs trace
3. **Post-execution** → `/ace reflect` (prompted automatically)
4. **Reflector** analyzes trace, evaluates strategies, generates insights
5. **Periodically** → `/ace curate` (after 5+ reflections)
6. **Curator** updates strategy scores, creates new strategies, deprecates failing ones

---

## Core Principles

### Code Execution (Always Enforced)

- **DRY**: Refactor repetitive logic (Rule of Three)
- **KISS**: Clear, minimal, easy to reason about
- **SRP**: Each function does one thing well
- **Separation of Concerns**: Decouple UI, state, backend
- **Fail Fast - Fail Loud**: Raise errors early, never suppress
- **CQS**: Commands or queries, never both
- **Modularity**: Reusable, isolated components

### Development Execution

- Verify information before presenting
- File-by-file changes only
- No apologies, understanding feedback, or summaries
- Preserve existing code and structures
- Single chunk edits per file
- Explicit variable names, consistent style
- Security-first approach
- Robust error handling and test coverage

Execute immediately upon request. No preamble. Deliver.

### Baby Steps Methodology

Every action adheres to:

1. **Smallest Possible Meaningful Change** - Single atomic step
2. **Process is Product** - Journey over destination
3. **One Accomplishment at a Time** - Focus singular
4. **Complete Each Step Fully** - No half-done states
5. **Incremental Validation** - Validate after every step
6. **Document with Focus** - Specific, focused detail

---

## Memory System

### Project-Level (Git-tracked)

```
./.agent-memory/
├── project-brief.md         # Foundation, scope
├── product-context.md       # Why, what, how
├── active-context.md        # Current focus (10-item sliding window)
├── system-patterns.md       # Architecture, decisions
├── tech-context.md          # Stack, constraints
├── progress.md              # Status, blockers
└── changelog.md             # Version history
```

### Global (Cross-project)

```
~/.agent-memory/
├── strategies/              # ACE playbook (primary)
├── patterns/                # Reusable solutions
├── learnings/               # Consolidated knowledge
└── projects/                # Project summaries
```

### Memory Commands

| Command | Purpose |
|---------|---------|
| `/memory-init` | Initialize project memory |
| `/memory-read` | Load all project memory |
| `/memory-search <q>` | Search project |
| `/memory-global <q>` | Search global |
| `/memory-update <s>` | Update active-context |
| `/memory-extract <p>` | Extract to global |

### Task Protocol

**Start:**
1. Check project registration
2. Read ALL `.agent-memory/` files
3. Search project for context
4. Load relevant strategies from ACE playbook

**During:**
- Update `active-context.md` (sliding window)
- Document patterns in `system-patterns.md`
- Log execution for ACE reflection

**Complete:**
1. Update memory files
2. Git commit with code
3. Run `/ace reflect` if significant task
4. Extract patterns to global if reusable

---

## Agent Commands

### Unified Interface

| Command | Action |
|---------|--------|
| `/agent explore <q>` | Codebase analysis |
| `/agent architect <f>` | Design planning |
| `/agent implement <t>` | Code execution |
| `/agent review [f]` | Code review |
| `/agent test <s>` | Test execution |

### Project Commands

| Command | Action |
|---------|--------|
| `/project-task <t>` | Full context task |
| `/project-plan <t>` | Sequential planning |
| `/project-review` | Consolidate learnings |
| `/project-status` | Show progress |
| `/project-next` | Get next task |

### Plan Commands

| Command | Action |
|---------|--------|
| `/plan-revise <i>` | Revise current plan |
| `/plan-reject` | Discard plan |
| `/act` | Execute plan |

---

## Hooks

Located in `~/.claude/hooks/`, registered in `~/.claude/settings.json`:

| Hook | Event | Matcher | Action |
|------|-------|---------|--------|
| `pre-implement.fish` | PreToolUse | Edit\|Write | Load memory prompt, show strategies |
| `post-task.fish` | PostToolUse | Edit\|Write | Log changes, suggest reflection after 10+ |
| `stop.fish` | Stop | * | Suggest memory update and git commit |
| `weekly-curation.fish` | Systemd timer | Sunday 09:00 | Notify if 5+ reflections pending |

### Automatic Behaviors

- **Memory detection**: On first Edit/Write, prompts to load project memory if .agent-memory/ exists
- **Strategy loading**: Analyzes file path/extension, shows applicable strategies
- **Change tracking**: All Edit/Write ops logged to `~/.claude/ace-sessions/YYYY-MM-DD.jsonl`
- **Reflection prompts**: After 10+ file changes per session
- **Session end**: Suggests `/memory-update` and git commit for uncommitted .agent-memory/ changes
- **Curation reminders**: Desktop notification via systemd timer

---

## Sequential Thinking

Use `mcp__sequentialthinking__sequentialthinking` for:
- Complex problem decomposition
- Iterative planning
- Analysis requiring course correction
- Multi-step solutions

Principles:
- Each thought builds on previous
- Adjust totalThoughts dynamically
- Express uncertainty explicitly
- Mark revisions
- Only finish when verified

---

## CLI Preferences

Fish shell. Modern tools:

| Tool | Instead of | Flags |
|------|------------|-------|
| `fd` | `find` | `--ignore-file .claudeignore --json` |
| `rg` | `grep` | `--ignore-file .claudeignore --json` |
| `sd` | `sed` | - |
| `bat` | `cat` | `-p` for piping |
| `eza` | `ls` | `--icons --git` |

Prefer JSON output for programmatic processing.

---

## Protected Repositories

| Repository | Main Branch | Remote |
|------------|-------------|--------|
| `nix-config` | PROTECTED | Cli MCP (gh) only |
| `nix-lib` | PROTECTED | Cli MCP (gh) only |
| `nix-secrets` | PROTECTED | Cli MCP (gh) only |
| `nix-keys` | PROTECTED | Cli MCP (gh) only |

Feature branch workflow required.

---

## Conventions

### Git Commits

Conventional Commits 1.0.0:
```
<type>[scope]: <description>

[body]

[footer]
```

Types: feat, fix, docs, style, refactor, test, chore

### Code Files

Add relative path comment on first line (second if shebang needed).

### Communication

English for all interactions and artifacts.

### Text Style

- Informative as required, not more
- Avoid ambiguity
- Be brief, be orderly
- Omit needless words
- Perfection: nothing left to take away

---

## Enforcement

### Manual
- [ ] Search for task context (task-specific)
- [ ] Extract reusable patterns to global (requires judgment)

### Automated (via Hooks)
- Memory load prompt on first Edit/Write (pre-implement hook)
- Strategy loading on Edit/Write (pre-implement hook)
- Change tracking to session log (post-task hook)
- Reflection prompts after 10+ changes (post-task hook)
- Memory update suggestion on stop (stop hook)
- Git commit suggestion for .agent-memory/ (stop hook)
- Curation reminders weekly (systemd timer)

---

## Documentation

- [Basic Memory](https://memory.basicmachines.co/)
- [ACE System](~/.claude/agents/README.md)
- [Hooks](~/.claude/hooks/README.md)
