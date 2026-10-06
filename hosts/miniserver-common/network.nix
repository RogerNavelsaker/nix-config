{ config, ... }:
{
  networking = {
    networkmanager.enable = false;
    wireless.enable = false;
    useNetworkd = true;
    useDHCP = false;
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;
    networks."10-wired-client" = {
      matchConfig.Name = "en*";
      networkConfig.DHCP = "ipv4";
    };
  };

  services.avahi = {
    enable = true;
    hostName = config.networking.hostName;
    publish = {
      addresses = true;
      workstation = true;
    };
  };
}
