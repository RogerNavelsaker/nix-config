# pkgs/default.nix
{ pkgs, lib }:
let
  here = ./.;

  # Discover packages in directory
  discoverPackages =
    dir:
    let
      entries = if builtins.pathExists dir then builtins.readDir dir else { };
    in
    lib.attrsets.filterAttrs (
      name: type:
      (type == "directory" && builtins.pathExists (dir + "/${name}/default.nix"))
      || (name != "default.nix" && lib.strings.hasSuffix ".nix" name && type == "regular")
    ) entries;

  # Build package set from directory
  buildPackageSet =
    pkgs': dir:
    let
      packageDirs = discoverPackages dir;
      stripNixSuffix = name: if lib.hasSuffix ".nix" name then lib.removeSuffix ".nix" name else name;
    in
    lib.mapAttrs' (
      name: _type: lib.nameValuePair (stripNixSuffix name) (pkgs'.callPackage (dir + "/${name}") { })
    ) packageDirs;
in
# Automatically discover and build all packages in this directory
buildPackageSet pkgs here
// {
  # Manual package overrides (applies to both flake packages and overlay)
  # my-custom-tool = pkgs.callPackage ./my-custom-tool { someOverride = ...; };
}
