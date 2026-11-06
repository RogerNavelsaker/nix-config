{ inputs, ... }:
{
  hostname = "agent-mara";
  nixpkgs = inputs.nixpkgs-mara;
  "home-manager" = inputs.home-manager-mara;
  system = "x86_64-linux";
  stateVersion = "26.05";
  users = [ "mara" ];
  features.opt-out = [ "impermanence" ];
}
