{
  diskoLib,
  diskoModule,
  lib,
  pkgs,
  self,
}:
import ./miniserver-disko-layout.nix {
  inherit
    diskoLib
    diskoModule
    lib
    pkgs
    self
    ;
  hostname = "nanoserver-01";
}
