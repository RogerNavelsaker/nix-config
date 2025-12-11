{ nix-lib, ... }:
let
  here = ./.;
in
{
  imports = nix-lib.scanModules here;
}
