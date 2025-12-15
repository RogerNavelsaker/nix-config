# hosts/iso/default.nix
{
  lib,
  nix-lib,
  config,
  modulesPath,
  inputs,
  ...
}:
let
  here = ./.;
in
{
  imports = (nix-lib.scanModules here) ++ [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    # Determinate Nix module for FlakeHub integration
    inputs.determinate.nixosModules.default
  ];

  # ISO image configuration
  image.baseName = lib.mkForce config.hostSpec.hostname;

  # Use NetworkManager (Determinate ISO default)
  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;
}
