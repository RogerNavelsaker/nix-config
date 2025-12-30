# devshells/common.nix
# Shared base configuration for all devshells
{
  inputs,
  pkgs,
  system,
}:
let
  # Common git-hooks check (optional, projects can override)
  mkGitHooks =
    src:
    inputs.git-hooks.lib.${system}.run {
      inherit src;
      hooks = {
        nixfmt-rfc-style.enable = true;
        deadnix.enable = true;
        statix.enable = true;
      };
    };
in
{
  # Base packages available in all devshells
  packages = with pkgs; [
    # Version control
    git

    # Modern CLI tools
    fd
    ripgrep
    bat
    eza
    jq

    # Nix tooling
    nixfmt-rfc-style
    deadnix
    statix
    nix-tree
    nixd
  ];

  # Common commands available in all devshells
  commands = [
    {
      name = "fmt";
      category = "validation";
      help = "Format nix files";
      command = "nixfmt .";
    }
    {
      name = "lint";
      category = "validation";
      help = "Run all linters (deadnix + statix)";
      command = "deadnix . && statix check .";
    }
  ];

  # Common startup scripts
  startup = {
    welcome.text = "";
  };

  # Export mkGitHooks for project-specific use
  inherit mkGitHooks;
}
