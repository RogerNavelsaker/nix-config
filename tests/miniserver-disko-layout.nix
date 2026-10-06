{
  diskoLib,
  diskoModule,
  lib,
  pkgs,
  self,
  hostname,
}:
let
  hostConfig = self.nixosConfigurations.${hostname}.config;
  rootPoolPath = hostConfig.appliance.update.rootPoolPath;
  storeSubvolume = "${hostConfig.appliance.storeName}_${hostConfig.appliance.rootVersion}";
  diskConfig = diskoLib.testLib.prepareDiskoConfig {
    disko.devices = hostConfig.disko.devices;
  } (builtins.tail diskoLib.testLib.devices);
in
pkgs.testers.runNixOSTest {
  name = "${hostname}-disko-layout";
  nodes.machine = {
    imports = [
      diskoModule
      diskConfig
    ];
    disko.enableConfig = false;
    boot.supportedFilesystems = [
      "btrfs"
      "vfat"
    ];
    environment.systemPackages = [
      pkgs.btrfs-progs
      pkgs.util-linux
    ];
    system.stateVersion = "25.11";
    virtualisation.emptyDiskImages = lib.mkForce [
      16384
      16384
      16384
      16384
    ];
  };
  testScript =
    { nodes, ... }:
    ''
      for cycle in range(2):
        machine.succeed("mkdir -p /mnt && mount -t tmpfs -o size=128M tmpfs /mnt")
        machine.succeed("test \"$(findmnt -n -o FSTYPE /mnt)\" = tmpfs")
        machine.succeed("${lib.getExe nodes.machine.system.build.format}")
        machine.succeed("${lib.getExe nodes.machine.system.build.mount}")
        machine.succeed("test \"$(findmnt -n -o FSTYPE /mnt${rootPoolPath})\" = btrfs")
        machine.succeed("btrfs filesystem show /mnt${rootPoolPath} | grep -q 'Total devices 2'")
        machine.succeed("btrfs subvolume list /mnt${rootPoolPath} | grep -Fq '${storeSubvolume}'")
        machine.succeed("btrfs filesystem df /mnt${rootPoolPath} | grep -q 'Data, RAID1'")
        machine.succeed("btrfs filesystem df /mnt${rootPoolPath} | grep -q 'Metadata, RAID1'")
        machine.succeed("btrfs filesystem df /mnt${rootPoolPath} | grep -q 'System, RAID1'")
        machine.succeed("test \"$(findmnt -n -o FSTYPE /mnt/persist)\" = btrfs")
        machine.succeed("btrfs filesystem show /mnt/persist | grep -q 'Total devices 2'")
        machine.succeed("umount -Rv /mnt")
        machine.succeed("echo yes | ${lib.getExe nodes.machine.system.build.destroy}")
        machine.succeed("echo yes | ${lib.getExe nodes.machine.system.build.destroy}")
    '';
}
