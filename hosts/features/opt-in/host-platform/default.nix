{ nix-lib, ... }:
{
  imports = nix-lib.scanModules ./.;
}
