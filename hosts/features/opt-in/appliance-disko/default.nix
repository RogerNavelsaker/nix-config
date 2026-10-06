{ nix-lib, ... }:
{
  imports = nix-lib.scanModules ./.;

  # Runtime mounts and swap are declared by the appliance features; Disko here
  # only supplies the explicit partition/layout scripts.
  disko.enableConfig = false;
}
