# users/features/opt-in/claude-code/default.nix
#
# Claude Code configuration with ACE (Agentic Context Engineering) system
# Opt-in feature for AI-assisted development
#
{ config, ... }:
let
  memory = import ./_lib/memory.nix;
  settings = import ./_lib/settings.nix { inherit config; };
  hooks = import ./_lib/hooks.nix;
  agents = import ./_lib/agents.nix;
in
{
  programs.claude-code = {
    enable = true;
    memory.text = memory;
    inherit (settings) settings;
    inherit hooks agents;
  };
}
