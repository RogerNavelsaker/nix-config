{ inputs, pkgs, ... }:
{
  imports = [ inputs.nixos-wsl.nixosModules.default ];

  wsl.enable = true;
  wsl.defaultUser = "admin";

  networking.hostName = "services";
  users.groups.admin = { };

  users.users.admin = {
    isNormalUser = true;
    group = "admin";
    extraGroups = [ "wheel" ];
    home = "/home/admin";
    createHome = true;
    shell = pkgs.bashInteractive;
  };

  virtualisation.podman.enable = true;

  services.tailscale = {
    enable = true;
    extraUpFlags = [
      "--hostname=ester-services"
      "--advertise-tags=tag:server"
    ];
  };

  networking.firewall.enable = true;
}
