{ inputs, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  scripts = import ./scripts {
    inherit pkgs;
    inherit (inputs.pog.packages.${system}) pog;
  };

  pre-commit-check = inputs.git-hooks.lib.${system}.run {
    src = ./.;
    hooks = import ./githooks.nix { inherit pkgs; };
  };
in
{
  default = inputs.devshell.legacyPackages.${system}.mkShell {
    name = "nix-config";

    motd = ''
      ╔════════════════════════════════════════════╗
      ║  NixOS Configuration Development Shell    ║
      ╚════════════════════════════════════════════╝

      Available hosts: nanoserver, iso
      Available home configs: rona@nanoserver

      Quick Commands:
        os switch             Build & switch NixOS (current host)
        os switch -H <host>   Build & switch NixOS (specific host)
        hm switch             Build & switch Home Manager
        hm switch -c <u@h>    Build & switch Home Manager (specific config)
        iso <action>          ISO management (build/run/stop/ssh/log)
        check                 Run all flake checks
        search <pkg>          Search nixpkgs
        menu                  Show all commands

      Run 'menu' for complete command list with categories.
    '';

    packages = with pkgs; [
      # Nix CLI helper (better UX for rebuilds)
      nh

      # Nix formatters and linters (used by git-hooks and manual commands)
      nixfmt-rfc-style
      deadnix
      statix

      # Nix analysis tools
      nix-tree
      nix-diff

      # Language servers
      nixd

      # Version control
      git

      # Build system
      gnumake

      # Virtualization
      qemu
      OVMF
    ];

    commands = [
      # System Management Category (using nh)
      {
        name = "os";
        category = "system";
        help = "NixOS operations: os switch|boot|test|build|generations [-H hostname]";
        command = ''
          nh os "$@"
        '';
      }
      {
        name = "hm";
        category = "system";
        help = "Home Manager operations: hm switch|build [-c user@host]";
        command = ''
          nh home "$@"
        '';
      }
      {
        name = "clean";
        category = "system";
        help = "Garbage collection: clean all|user|system [--keep-since Nd] [--keep N]";
        command = ''
          nh clean "$@"
        '';
      }
      {
        name = "search";
        category = "system";
        help = "Search nixpkgs: search <query>";
        command = ''
          nh search "$@"
        '';
      }

      # Validation & Quality Category
      {
        name = "check";
        category = "validation";
        help = "Run all flake checks (format, syntax, dead code)";
        command = "nix flake check";
      }
      {
        name = "fmt";
        category = "validation";
        help = "Format all nix files with nixfmt-rfc-style";
        command = "nixfmt .";
      }
      {
        name = "lint-deadcode";
        category = "validation";
        help = "Find and report unused code (deadnix)";
        command = "deadnix .";
      }
      {
        name = "lint-patterns";
        category = "validation";
        help = "Check for anti-patterns (statix)";
        command = "statix check .";
      }
      {
        name = "lint-patterns-fix";
        category = "validation";
        help = "Auto-fix anti-patterns (statix)";
        command = "statix fix .";
      }
      {
        name = "show";
        category = "validation";
        help = "Display flake outputs structure";
        command = "nix flake show";
      }

      # Flake Management Category
      {
        name = "update";
        category = "flake";
        help = "Update all flake inputs to latest versions";
        command = "nix flake update";
      }
      {
        name = "update-input";
        category = "flake";
        help = "Update specific input: update-input <input-name>";
        command = ''
          if [ -z "''${1:-}" ]; then
            echo "Usage: update-input <input-name>"
            echo "Example: update-input nixpkgs"
            exit 1
          fi
          nix flake lock --update-input "$1"
        '';
      }

      # ISO Management Category
      {
        name = "iso";
        category = "iso";
        help = "ISO management: iso <build|run|stop|restart|status|ssh|log> (--help for details)";
        command = ''
          ${scripts.iso}/bin/iso "$@"
        '';
      }

    ];

    devshell.startup = {
      welcome.text = "";
      git-hooks.text = pre-commit-check.shellHook;
      nh-config.text = ''
        # Set NH_FLAKE for nh to auto-detect flake location
        export NH_FLAKE="$(pwd)"
      '';
    };
  };
}
