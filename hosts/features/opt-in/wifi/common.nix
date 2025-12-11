_: {
  # Enable iwd daemon
  networking.wireless.iwd = {
    enable = true;
    settings = {
      General.EnableNetworkConfiguration = false; # Using systemd-networkd
      Settings.AutoConnect = true;
    };
  };

  # Ensure /var/lib/iwd exists before secrets activation runs
  # This handles first boot before impermanence has restored the directory
  systemd.tmpfiles.rules = [
    "d /var/lib/iwd 0700 root root -"
  ];

  environment.persistence = {
    "/persist".directories = [
      {
        directory = "/var/lib/iwd";
      }
    ];
  };
}
