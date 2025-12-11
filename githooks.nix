# githooks.nix - Git hooks configuration using cachix/git-hooks.nix
{ pkgs }:
{
  # Formatting
  nixfmt-rfc-style.enable = true;

  # Linting
  deadnix.enable = true;
  statix.enable = true;

  # Syntax validation
  nix-syntax = {
    enable = true;
    name = "nix-syntax";
    description = "Validate Nix syntax with nix-instantiate --parse";
    entry = "${pkgs.nix}/bin/nix-instantiate --parse";
    files = "\\.nix$";
    pass_filenames = true;
  };

  # Post-merge notification for flake changes
  flake-changed-notify = {
    enable = true;
    name = "flake-changed-notify";
    description = "Notify when flake.nix or flake.lock changed after merge";
    stages = [ "post-merge" ];
    entry = toString (
      pkgs.writeShellScript "flake-changed-notify" ''
        changed=$(git diff-tree -r --name-only ORIG_HEAD HEAD 2>/dev/null | grep -E '^(flake\.nix|flake\.lock)$' || true)
        if [ -n "$changed" ]; then
          echo ""
          echo "╔════════════════════════════════════════════════════════════╗"
          echo "║  NOTE: Flake files changed after merge                     ║"
          echo "╠════════════════════════════════════════════════════════════╣"
          echo "║  Changed: $changed"
          echo "║  Consider running: direnv reload or nix develop            ║"
          echo "╚════════════════════════════════════════════════════════════╝"
          echo ""
        fi
      ''
    );
    always_run = true;
    pass_filenames = false;
  };
}
