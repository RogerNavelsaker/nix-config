_: {
  networking = {
    networkmanager.enable = false;
    wireless.enable = false;
    useNetworkd = true;
    useDHCP = false;
  };

  systemd.network = {
    enable = true;
    wait-online.enable = false;
    networks = {
      "10-wired-client" = {
        matchConfig.Name = "en*";
        networkConfig.DHCP = "ipv4";
        dhcpV4Config.RouteMetric = 100;
      };
      "15-qemu-wired-client" = {
        matchConfig.Name = "eth*";
        networkConfig.DHCP = "ipv4";
        dhcpV4Config.RouteMetric = 150;
      };
      "20-wlan-client" = {
        matchConfig.Name = "wl*";
        networkConfig.DHCP = "ipv4";
        dhcpV4Config.RouteMetric = 200;
      };
    };
  };

  services.avahi = {
    enable = true;
    hostName = "nanoserver";
    publish = {
      addresses = true;
      workstation = true;
    };
  };
}
