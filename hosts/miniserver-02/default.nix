{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./devices.nix
    ./hardware.nix
    ../miniserver-common/network.nix
    ../miniserver-common/persistence.nix
    ../miniserver-common/secrets.nix
    ../miniserver-common/ssh.nix
  ];

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";
  services.journald.storage = "volatile";
  boot.tmp.useTmpfs = true;
  networking.firewall.enable = true;
}
