# devshells/nix-config.nix
# NixOS configuration development shell
{
  inputs,
  pkgs,
  mkProjectShell,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  pre-commit-check = inputs.git-hooks.lib.${system}.run {
    src = ./..;
    hooks = import ../githooks.nix { inherit pkgs; };
  };
in
mkProjectShell {
  name = "nix-config";

  motd = ''
    ╔════════════════════════════════════════════╗
    ║  NixOS Configuration Development Shell    ║
    ╚════════════════════════════════════════════╝

    Quick Commands:
      os switch [host]      Build & switch NixOS
      hm switch [user@host] Build & switch Home Manager
      check                 Run all flake checks
      menu                  Show all commands
  '';

  packages = with pkgs; [
    nh
    nix-diff
    nixd
    gnumake
  ];

  commands = [
    {
      name = "os";
      category = "system";
      help = "NixOS: os switch [hostname] | os boot [hostname] | os test [hostname]";
      command = ''
        local action="$1"
        shift
        if [[ -n "$1" && "$1" != -* ]]; then
          nh os "$action" -H "$1" "''${@:2}"
        else
          nh os "$action" "$@"
        fi
      '';
    }
    {
      name = "hm";
      category = "system";
      help = "Home Manager: hm switch [user@host] | hm build [user@host]";
      command = ''
        local action="$1"
        shift
        if [[ -n "$1" && "$1" != -* ]]; then
          nh home "$action" -c "$1" "''${@:2}"
        else
          nh home "$action" "$@"
        fi
      '';
    }
    {
      name = "clean";
      category = "system";
      help = "Garbage collection: clean all|user|system";
      command = ''nh clean "$@"'';
    }
    {
      name = "search";
      category = "system";
      help = "Search nixpkgs";
      command = ''nh search "$@"'';
    }
    {
      name = "check";
      category = "validation";
      help = "Run all flake checks";
      command = "nix flake check";
    }
    {
      name = "show";
      category = "validation";
      help = "Display flake outputs";
      command = "nix flake show";
    }
    {
      name = "update";
      category = "flake";
      help = "Update all flake inputs";
      command = "nix flake update";
    }
  ];

  startup = {
    git-hooks.text = pre-commit-check.shellHook;
    nh-config.text = ''
      export NH_FLAKE="$(pwd)"
    '';
  };
}
