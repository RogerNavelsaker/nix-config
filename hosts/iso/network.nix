{ lib, ... }:
{
  # Networking configuration
  networking = {
    networkmanager.enable = lib.mkForce false;
    useNetworkd = true;
    useDHCP = false;
    wireless.enable = false;
  };

  systemd.network = {
    enable = true;
    networks = {
      "10-lan" = {
        matchConfig.Name = "en*";
        networkConfig.DHCP = "ipv4";
        dhcpV4Config.RouteMetric = 100;
      };
      "20-wlan" = {
        matchConfig.Name = "wlan*";
        networkConfig.DHCP = "ipv4";
        dhcpV4Config.RouteMetric = 200;
      };
    };
  };
}
