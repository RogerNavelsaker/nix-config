# hosts/iso/default.nix
{
  lib,
  nix-lib,
  config,
  modulesPath,
  ...
}:
let
  here = ./.;
in
{
  imports = (nix-lib.scanModules here) ++ [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
  ];

  # ISO image configuration
  image.baseName = lib.mkForce config.hostSpec.hostname;
}
