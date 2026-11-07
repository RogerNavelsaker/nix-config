{
  diskoLib,
  diskoModule,
  lib,
  pkgs,
  self,
}:
let
  hostConfig = self.nixosConfigurations.nanoserver-01-update-v4-a.config;
  dataUuid = hostConfig.appliance.btrfs.dataUuid;
  dataDevice = "/dev/disk/by-uuid/${dataUuid}";
  applianceName = hostConfig.appliance.name;
  deviceScanScript = hostConfig.boot.initrd.systemd.services."${applianceName}-btrfs-device-scan".script;
  rootResetScript = hostConfig.boot.initrd.systemd.services."${applianceName}-root-reset".script;
  diskConfig = diskoLib.testLib.prepareDiskoConfig {
    disko.devices = hostConfig.disko.devices;
  } (builtins.tail diskoLib.testLib.devices);
in
pkgs.testers.runNixOSTest {
  name = "nanoserver-v4-root-boot";

  nodes.machine = { lib, pkgs, ... }:
    {
      imports = [ diskoModule diskConfig ];

      disko.enableConfig = false;
      boot.supportedFilesystems = [ "btrfs" "vfat" ];
      boot.loader.systemd-boot.enable = true;
      boot.loader.efi.canTouchEfiVariables = true;
      environment.systemPackages = [ pkgs.btrfs-progs pkgs.util-linux ];
      system.stateVersion = "25.11";

      virtualisation = {
        emptyDiskImages = lib.mkForce [ 16384 16384 16384 16384 ];
        mountHostNixStore = true;
        useBootLoader = true;
        useEFIBoot = true;
      };

      specialisation.nanoserver-v4-root.configuration = {
        boot.initrd.systemd.enable = true;
        boot.initrd.supportedFilesystems.btrfs = true;
        virtualisation.fileSystems."/" = lib.mkForce {
          device = dataDevice;
          fsType = "btrfs";
          options = [
            "degraded"
            "compress=zstd:1"
            "noatime"
            "subvol=@root"
            "x-initrd.mount"
          ];
        };
        boot.initrd.systemd.services = {
          "${applianceName}-btrfs-device-scan" = {
            description = "Scan mirrored Btrfs root members before mounting the store";
            wantedBy = [ "initrd-root-device.target" ];
            before = [ "initrd-root-device.target" ];
            after = [ "systemd-udev-settle.service" ];
            requires = [ "systemd-udev-settle.service" ];
            serviceConfig.Type = "oneshot";
            path = [ pkgs.btrfs-progs pkgs.coreutils pkgs.systemd ];
            script = deviceScanScript;
          };
          "${applianceName}-root-reset" = {
            description = "Restore the ephemeral Btrfs root before mounting sysroot";
            after = [ "initrd-root-device.target" ];
            before = [ "sysroot.mount" ];
            requires = [ "initrd-root-device.target" ];
            requiredBy = [ "sysroot.mount" ];
            unitConfig.DefaultDependencies = false;
            serviceConfig.Type = "oneshot";
            serviceConfig.RemainAfterExit = true;
            path = [ pkgs.btrfs-progs pkgs.coreutils pkgs.util-linux ];
            environment.PATH = lib.mkForce (lib.makeBinPath [ pkgs.btrfs-progs pkgs.coreutils pkgs.util-linux ] + ":/bin:/sbin");
            script = rootResetScript;
          };
        };

        fileSystems."/" = lib.mkForce {
          device = dataDevice;
          fsType = "btrfs";
          options = [
            "degraded"
            "compress=zstd:1"
            "noatime"
            "subvol=@root"
            "x-initrd.mount"
          ];
        };
        virtualisation.fileSystems."/persist" = lib.mkForce {
          device = dataDevice;
          fsType = "btrfs";
          options = [ "subvol=@persist" "degraded" ];
          neededForBoot = true;
        };
      };
    };

  testScript =
    { nodes, ... }:
    ''
      machine.succeed("${lib.getExe nodes.machine.system.build.format}")
      machine.succeed("${lib.getExe nodes.machine.system.build.mount}")
      machine.succeed("printf stale > /mnt/root-reset-marker")
      machine.succeed("printf persist > /mnt/persist/root-reset-marker")
      machine.succeed("umount -Rv /mnt")

      machine.succeed("bootctl set-default nixos-generation-1-specialisation-nanoserver-v4-root.conf")
      machine.crash()
      machine.wait_for_unit("multi-user.target")
      machine.succeed("test \"$(findmnt -n -o FSTYPE /)\" = btrfs")
      machine.succeed("findmnt -n -o FSROOT / | grep -Fxq '/@root'")
      machine.succeed("test ! -e /root-reset-marker")
      machine.succeed("mountpoint -q /persist")
      machine.succeed("test \"$(cat /persist/root-reset-marker)\" = persist")

      machine.succeed("bootctl set-default nixos-generation-1.conf")
      machine.crash()
      machine.wait_for_unit("multi-user.target")
      machine.succeed("mkdir -p /mnt && mount -t btrfs -o degraded,subvolid=5 ${dataDevice} /mnt")
      machine.succeed("btrfs subvolume list -o /mnt/@root | awk '{print $NF}' | sort -r | while read subvol; do btrfs subvolume delete \"/mnt/$subvol\"; done && btrfs subvolume delete /mnt/@root")
      machine.succeed("umount /mnt")

      machine.succeed("bootctl set-default nixos-generation-1-specialisation-nanoserver-v4-root.conf")
      machine.crash()
      machine.wait_for_unit("multi-user.target")
      machine.succeed("test \"$(findmnt -n -o FSTYPE /)\" = btrfs")
      machine.succeed("findmnt -n -o FSROOT / | grep -Fxq '/@root'")
      machine.succeed("test ! -e /root-reset-marker")
      machine.succeed("test \"$(cat /persist/root-reset-marker)\" = persist")
    '';
}
