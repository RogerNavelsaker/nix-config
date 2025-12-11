# overlays/default.nix
{ inputs, lib }:
let
  # Channel overlay helper
  mkChannelOverlay = name: src: final: _prev: {
    ${name} = import src {
      inherit (final.stdenv.hostPlatform) system;
      config.allowUnfree = true;
      config.nvidia.acceptLicense = true;
    };
  };

  stable-packages = mkChannelOverlay "stable" inputs.nixpkgs-stable;
  unstable-packages = mkChannelOverlay "unstable" inputs.nixpkgs-unstable;
  master-packages = mkChannelOverlay "master" inputs.nixpkgs-master;

  flake-inputs = final: _: {
    inputs = builtins.mapAttrs (
      _: flake:
      let
        legacyPackages = (flake.legacyPackages or { }).${final.stdenv.hostPlatform.system} or { };
        packages = (flake.packages or { }).${final.stdenv.hostPlatform.system} or { };
      in
      if legacyPackages != { } then legacyPackages else packages
    ) inputs;
  };

  # Pog overlay - provides pog.pog function for building CLI tools
  pog-overlay =
    final: _prev:
    let
      pogPkgs = inputs.pog.packages.${final.stdenv.hostPlatform.system} or { };
    in
    {
      pog =
        pogPkgs.pog or (throw "pog package not available for system ${final.stdenv.hostPlatform.system}");
    };

  additions =
    final: _prev:
    import ../pkgs {
      pkgs = final;
      inherit lib;
    };

  modifications = _final: _prev: {
    # Example: patch a package
    # somePackage = addPatches prev.somePackage [./patches/some-fix.patch];

    # Example: override attributes
    # anotherPackage = prev.anotherPackage.overrideAttrs (old: {
    #   buildInputs = (old.buildInputs or []) ++ [final.someLib];
    # });
  };
in
{
  inherit
    stable-packages
    unstable-packages
    master-packages
    flake-inputs
    pog-overlay
    additions
    modifications
    ;

  default =
    final: prev:
    (stable-packages final prev)
    // (unstable-packages final prev)
    // (master-packages final prev)
    // (flake-inputs final prev)
    // (pog-overlay final prev)
    // (additions final prev)
    // (modifications final prev);
}
