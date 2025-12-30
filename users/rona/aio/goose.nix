# users/rona/aio/goose.nix
#
# Goose CLI configuration - primary interface using claude-code as backend
#
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  # Check if llm-agents input is available
  hasLlmAgents = inputs ? llm-agents;
  goose-cli = if hasLlmAgents then inputs.llm-agents.packages.${pkgs.system}.goose-cli else null;

  # Import local lib for recipe generation
  localLib = import ./lib.nix { inherit lib; };
  inherit (localLib) mkGooseRecipe;

  # Goose main config
  gooseConfig = ''
    GOOSE_PROVIDER: claude-code
    GOOSE_MODEL: sonnet
    GOOSE_MODE: auto
    extensions:
      developer:
        enabled: true
        type: builtin
      memory:
        enabled: true
        type: builtin
    slash_commands:
      - command: ace
        recipe_path: ${config.home.homeDirectory}/.config/goose/recipes/ace.yaml
      - command: memory
        recipe_path: ${config.home.homeDirectory}/.config/goose/recipes/memory.yaml
      - command: project
        recipe_path: ${config.home.homeDirectory}/.config/goose/recipes/project.yaml
      - command: agent
        recipe_path: ${config.home.homeDirectory}/.config/goose/recipes/agent.yaml
      - command: plan
        recipe_path: ${config.home.homeDirectory}/.config/goose/recipes/plan.yaml
  '';

  # Define recipes - unified command interfaces
  gooseRecipes = {
    ace = mkGooseRecipe {
      name = "ACE System";
      description = "Unified ACE interface for agentic context engineering";
      prompt = ''
        ACE (Agentic Context Engineering) INTERFACE: {{ args }}

        Parse the first word as subcommand, remaining words as arguments.

        ## Subcommands

        ### `generate <task>` | `gen <task>`
        Execute task with strategy retrieval from playbook.

        ### `reflect [execution-id]` | `ref [id]`
        Analyze execution trace and generate insights.

        ### `curate [scope]` | `cur [scope]`
        Update playbook strategies from reflections.
        Scope: full | incremental | category:<name>

        ### `loop <task>`
        Full ACE loop: generate -> reflect -> curate (if needed).

        ### `status`
        Show ACE system status: strategies, executions, reflections.

        ### `strategies [category]`
        List available strategies.

        ### `playbook`
        Show playbook health and recommendations.

        ### `help`
        Show this help message.

        Execute the appropriate action based on subcommand.
      '';
      parameters = [
        {
          key = "args";
          type = "string";
          requirement = "optional";
        }
      ];
    };

    memory = mkGooseRecipe {
      name = "Memory Bank";
      description = "Unified memory bank interface";
      prompt = ''
        MEMORY BANK INTERFACE: {{ args }}

        Parse the first word as subcommand, remaining words as arguments.

        ## Subcommands

        ### `init [project-name]`
        Initialize project memory bank in `./.agent-memory/`.
        Creates: projectBrief, productContext, activeContext, systemPatterns, techContext, progress, changelog.

        ### `read`
        Read ALL project memory bank files to build context.
        MANDATORY before starting any task.

        ### `search <query>`
        Search project memory for task-related context.

        ### `global <query>`
        Search global memory bank for reusable patterns and learnings.

        ### `update <summary>`
        Update activeContext and progress after completing work.
        Maintains 10-item sliding window in activeContext.

        ### `extract <pattern-name>`
        Extract reusable pattern from current project to global memory.

        ### `activity [timeframe]`
        Show recent activity across projects.
        Timeframe: today, yesterday, 7d, 30d, etc.

        ### `help`
        Show this help message.

        Execute the appropriate action based on subcommand.
      '';
      parameters = [
        {
          key = "args";
          type = "string";
          requirement = "optional";
        }
      ];
    };

    project = mkGooseRecipe {
      name = "Project Workflow";
      description = "Unified project workflow interface";
      prompt = ''
        PROJECT WORKFLOW INTERFACE: {{ args }}

        Parse the first word as subcommand, remaining words as arguments.

        ## Subcommands

        ### `status`
        Show current project status from memory bank.
        Displays: current focus, progress, blockers, next steps.

        ### `next`
        Get the next prioritized task from project memory.
        Reads progress.md and activeContext.md to determine.

        ### `task <description>`
        Start a task with full memory context and tracking.
        1. Read all memory files
        2. Search for related context
        3. Load relevant strategies
        4. Execute task
        5. Update memory on completion

        ### `plan <description>`
        Plan task implementation without executing.
        Uses sequential thinking for step-by-step approach.

        ### `review [summary]`
        Review completed work and extract learnings.
        Updates progress.md, activeContext.md, and potentially global patterns.

        ### `help`
        Show this help message.

        Execute the appropriate action based on subcommand.
      '';
      parameters = [
        {
          key = "args";
          type = "string";
          requirement = "optional";
        }
      ];
    };

    agent = mkGooseRecipe {
      name = "Agent Spawning";
      description = "Unified agent spawning interface";
      prompt = ''
        AGENT SPAWNING INTERFACE: {{ args }}

        Parse the first word as agent type, remaining words as task.

        ## Agent Types

        ### `explore <question-or-area>`
        Spawn explore agent for codebase analysis.
        Thoroughness levels: quick, medium, very thorough.
        Outputs: key files, architecture, code snippets, patterns.

        ### `architect <feature-or-system>`
        Spawn architect agent for design planning.
        Loads systemPatterns and techContext first.
        Outputs: architecture diagram, components, file structure, implementation order.

        ### `implement <task>`
        Spawn implementation agent.
        Loads current-plan (if exists) and systemPatterns.
        Follows DRY, KISS, SRP principles.

        ### `review [file-or-scope]`
        Spawn code review agent.
        Default scope: git diff HEAD~1.
        Checks: correctness, security, performance, style.

        ### `test <scope-or-command>`
        Spawn test agent.
        Modes: write (create tests), run (execute tests), analyze.

        ### `help`
        Show this help message.

        Spawn the appropriate agent based on type.
      '';
      parameters = [
        {
          key = "args";
          type = "string";
          requirement = "optional";
        }
      ];
    };

    plan = mkGooseRecipe {
      name = "Plan Mode";
      description = "Unified plan mode interface";
      prompt = ''
        PLAN MODE INTERFACE: {{ args }}

        Parse the first word as subcommand, remaining words as arguments.

        ## Subcommands

        ### `create <task>` (default)
        Enter plan mode for task implementation.
        1. Explore codebase thoroughly
        2. Design implementation approach
        3. Present plan for approval
        4. Use AskUserQuestion if needed

        ### `act`
        Execute the current plan.
        1. Load current-plan from memory
        2. Convert steps to TodoWrite items
        3. Execute step-by-step with validation
        4. Update memory on completion

        ### `revise <instructions>`
        Revise the current plan with feedback.
        Modifies existing plan based on instructions.

        ### `reject [new-task]`
        Discard current plan.
        Optionally start fresh with new task.

        ### `show`
        Display the current plan.

        ### `help`
        Show this help message.

        Execute the appropriate action based on subcommand.
      '';
      parameters = [
        {
          key = "args";
          type = "string";
          requirement = "optional";
        }
      ];
    };
  };

in
{
  # Conditional goose-cli installation
  home.packages = lib.optional hasLlmAgents goose-cli;

  # Warning if llm-agents not available
  warnings = lib.optional (
    !hasLlmAgents
  ) "llm-agents.nix input not found. goose-cli will not be installed.";

  # Goose XDG configuration
  xdg.configFile = lib.mkIf hasLlmAgents (
    {
      "goose/config.yaml".text = gooseConfig;
    }
    // (lib.mapAttrs' (name: recipe: {
      name = "goose/recipes/${name}.yaml";
      value.text = recipe;
    }) gooseRecipes)
  );
}
