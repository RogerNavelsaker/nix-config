{ inputs, ... }:
{
  ester-desktop = {
    hostname = "ester-desktop";
    users = [ "admin" ];
    system = "x86_64-linux";
    stateVersion = "26.05";
    nixpkgs = inputs.nixpkgs;
    home-manager = inputs.home-manager;
  };
}
