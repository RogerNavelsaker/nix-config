{ inputs, ... }:
{
  imports = [
    inputs.disko.nixosModules.disko
    ./devices.nix
    ./hardware.nix
    ./network.nix
    ./persistence.nix
    ./ssh.nix
    ./secrets.nix
  ];

  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # Keep routine logs in RAM; durable application state belongs on the NVMe mirror.
  services.journald.storage = "volatile";
  boot.tmp.useTmpfs = true;

  networking.firewall.enable = true;
}
