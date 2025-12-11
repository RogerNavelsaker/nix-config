# hosts/nanoserver/default.nix
{
  pkgs,
  ...
}:
{
  # Boot loader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Root filesystem (placeholder - customize for your system)
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
  };

  # Networking
  networking.networkmanager.enable = true;

  # Time zone and locale
  time.timeZone = "UTC";
  i18n.defaultLocale = "en_US.UTF-8";

  # User account
  users.users.rona = {
    isNormalUser = true;
    description = "Rona";
    group = "rona";
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    initialPassword = "changeme";
  };

  users.groups.rona = { };

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    curl
  ];

  # Enable SSH
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "no";
  };

  # Firewall
  networking.firewall.enable = true;
}
