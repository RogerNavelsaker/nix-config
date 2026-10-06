# shell.nix
# Fallback devshell for devenv — uses plain mkShell (harmonized with nix-keys pattern)
{ inputs, pkgs, ... }:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  pre-commit-check = inputs.git-hooks.lib.${system}.run {
    src = ./.;
    hooks = import ./githooks.nix { inherit pkgs; };
  };
in
pkgs.mkShell {
  name = "nix-config";

  packages = with pkgs; [
    nh
    nix-diff
    gnumake
  ];

  shellHook = ''
    ${pre-commit-check.shellHook}
    export NH_FLAKE="$(pwd)"
  '';
}
