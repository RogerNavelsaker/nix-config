{
  config,
  lib,
  nix-lib,
  ...
}:
{
  fileSystems."/persist" = {
    device = lib.mkForce "/dev/disk/by-uuid/${config.appliance.btrfs.dataUuid}";
    fsType = "btrfs";
    options = [
      "subvol=@persist"
      "compress=zstd:1"
      "noatime"
      "degraded"
    ];
    neededForBoot = true;
  };

  environment.persistence."/persist".files = [
    "/etc/ssh/ssh_host_ed25519_key"
    "/etc/ssh/ssh_host_ed25519_key.pub"
  ];

  # Keep the shared high-write paths on the appliance's NVMe persistence pool.
  environment.persistence."/persist".directories =
    nix-lib.impermanence.mkPersistDirs "root" "root" "0755"
      [
        "/var/cache"
        "/var/tmp"
      ];
}
