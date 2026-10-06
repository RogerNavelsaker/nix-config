{ config, lib, ... }:
{
  # NixOS's swap submodule currently reads label while merging the device
  # option. Supply a placeholder but force the real PARTUUID path so no
  # filesystem label is created or used.
  swapDevices = lib.mkForce [
    {
      device = lib.mkForce "/dev/disk/by-partuuid/${config.appliance.btrfs.swapPartUuidA}";
      label = "unused";
      priority = 10;
      randomEncryption = false;
      discardPolicy = "once";
    }
    {
      device = lib.mkForce "/dev/disk/by-partuuid/${config.appliance.btrfs.swapPartUuidB}";
      label = "unused";
      priority = 10;
      randomEncryption = false;
      discardPolicy = "once";
    }
  ];
}
