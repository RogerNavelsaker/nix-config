# devshells/default.nix
# Entry point for all devshells — uses plain mkShell (harmonized with nix-keys pattern)
{
  inputs,
  pkgs,
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  common = import ./common.nix { inherit inputs pkgs system; };

  # Helper: merge common config with project-specific, using mkShell
  mkProjectShell =
    {
      name,
      motd ? "",
      packages ? [ ],
      commands ? [ ],
      shellHook ? "",
      env ? { },
    }:
    pkgs.mkShell {
      inherit name;
      packages = common.packages ++ packages;
      shellHook =
        (if motd != "" then "echo -e '${motd}'" else "")
        + common.shellHook
        + (builtins.concatStringsSep "\n" (map (c: "alias ${c.name}='${c.command}'") commands))
        + shellHook;
      env = common.env // env;
    };
in
{
  # Default shell (nix-config)
  default = import ./nix-config.nix {
    inherit
      inputs
      pkgs
      mkProjectShell
      common
      ;
  };

  # Nix ecosystem shells
  nix-config = import ./nix-config.nix {
    inherit
      inputs
      pkgs
      mkProjectShell
      common
      ;
  };
  # Base shell without motd (for layered .envrc remote reference)
  nix-config-base = import ./nix-config.nix {
    inherit
      inputs
      pkgs
      common
      ;
    mkProjectShell =
      args:
      mkProjectShell (
        args
        // {
          motd = "";
        }
      );
  };
  nix-repos = import ./nix-repos.nix {
    inherit
      inputs
      pkgs
      mkProjectShell
      common
      ;
  };
  nix-lib = import ./nix-lib.nix {
    inherit
      inputs
      pkgs
      mkProjectShell
      common
      ;
  };
  nix-keys = import ./nix-keys.nix {
    inherit
      inputs
      pkgs
      mkProjectShell
      common
      ;
  };
  nix-secrets = import ./nix-secrets.nix {
    inherit
      inputs
      pkgs
      mkProjectShell
      common
      ;
  };

  # Project shells
  senshac = import ./senshac.nix {
    inherit
      inputs
      pkgs
      mkProjectShell
      common
      ;
  };
  modern-cli-mcp = import ./modern-cli-mcp.nix {
    inherit
      inputs
      pkgs
      mkProjectShell
      common
      ;
  };
  codebase-mcp = import ./codebase-mcp.nix {
    inherit
      inputs
      pkgs
      mkProjectShell
      common
      ;
  };
}
