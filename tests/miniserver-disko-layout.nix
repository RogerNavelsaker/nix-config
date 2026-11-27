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
  isMiniserver = lib.hasPrefix "miniserver-" hostname;
  inherit (hostConfig.appliance.update) rootPoolPath;
  storeSubvolume = "${hostConfig.appliance.storeName}_${hostConfig.appliance.rootVersion}";

  hostKeyPaths = builtins.map (hostKey: hostKey.path) (
    builtins.filter (hostKey: hostKey.type == "ed25519") hostConfig.services.openssh.hostKeys
  );
  rootResetScript =
    if hostConfig.appliance.rootStorage == "nvme-btrfs" then
      hostConfig.boot.initrd.systemd.services."${hostConfig.appliance.name}-root-reset".script
    else
      "";

  rootBlankPostCreateHook =
    hostConfig.disko.devices.disk.nvmeB.content.partitions.data.content.postCreateHook;
  rootResetTestScript = lib.optionalString (hostConfig.appliance.rootStorage == "nvme-btrfs") ''
    machine.succeed("device=${dataDevice} bash /etc/nanoserver-root-blank-hook.sh")
    machine.succeed("mkdir -p /mnt && mount -t btrfs -o subvolid=5 ${dataDevice} /mnt")
    machine.succeed("btrfs property set -ts /mnt/@root-blank ro false && printf guard > /mnt/@root-blank/hook-marker")
    machine.succeed("umount -Rv /mnt")
    machine.fail("device=${dataDevice} bash /etc/nanoserver-root-blank-hook.sh")
    machine.succeed("mkdir -p /mnt && mount -t btrfs -o subvolid=5 ${dataDevice} /mnt")
    machine.succeed("test -e /mnt/@root-blank/hook-marker && test \"$(btrfs property get -ts /mnt/@root-blank ro)\" = \"ro=false\"")
    machine.succeed("rm /mnt/@root-blank/hook-marker && btrfs property set -ts /mnt/@root-blank ro true")
    machine.succeed("umount -Rv /mnt")
    machine.succeed("bash /etc/nanoserver-root-reset.sh")
    machine.succeed("mkdir -p /mnt && mount -t btrfs -o subvol=@root ${dataDevice} /mnt")
    machine.succeed("test ! -e /mnt/root-stale")
    machine.succeed("mkdir -p /mnt/persist && mount -t btrfs -o subvol=@persist ${dataDevice} /mnt/persist")
    machine.succeed("test \"$(cat /mnt/persist/root-persist)\" = keep")
    machine.succeed("printf stale-again > /mnt/root-stale")
    machine.succeed("umount -Rv /mnt")
    machine.succeed("bash /etc/nanoserver-root-reset.sh")
    machine.succeed("mkdir -p /mnt && mount -t btrfs -o subvolid=5 ${dataDevice} /mnt")
    machine.succeed("btrfs subvolume delete /mnt/@root")
    machine.succeed("umount -Rv /mnt")
    machine.succeed("bash /etc/nanoserver-root-reset.sh")
    machine.succeed("mkdir -p /mnt && mount -t btrfs -o subvolid=5 ${dataDevice} /mnt")
    machine.succeed("btrfs subvolume show /mnt/@root")
    machine.succeed("test \"$(btrfs property get -ts /mnt/@root-blank ro)\" = \"ro=true\"")
    machine.succeed("printf keep > /mnt/@root/failure-marker")
    machine.succeed("btrfs subvolume snapshot -r /mnt/@root-blank /mnt/@root-blank-backup")
    machine.succeed("btrfs subvolume delete /mnt/@root-blank")
    machine.succeed("umount -Rv /mnt")
    machine.fail("bash /etc/nanoserver-root-reset.sh")
    machine.succeed("mkdir -p /mnt && mount -t btrfs -o subvol=@root ${dataDevice} /mnt")
    machine.succeed("test -e /mnt/failure-marker")
    machine.succeed("umount -Rv /mnt")
    machine.succeed("mkdir -p /mnt && mount -t btrfs -o subvolid=5 ${dataDevice} /mnt")
    machine.succeed("btrfs subvolume snapshot -r /mnt/@root-blank-backup /mnt/@root-blank")
    machine.succeed("btrfs subvolume delete /mnt/@root-blank-backup")
    machine.succeed("umount -Rv /mnt")
    machine.succeed("bash /etc/nanoserver-root-reset.sh")
    machine.succeed("mkdir -p /mnt && mount -t btrfs -o subvol=@root ${dataDevice} /mnt")
    machine.succeed("test ! -e /mnt/failure-marker")
    machine.succeed("umount -Rv /mnt")
  '';
  inherit (hostConfig.appliance.btrfs) dataUuid;
  dataDevice = "/dev/disk/by-uuid/${dataUuid}";
  diskConfig = diskoLib.testLib.prepareDiskoConfig {
    disko.devices = hostConfig.disko.devices;
  } (builtins.tail diskoLib.testLib.devices);
in
assert !isMiniserver || hostKeyPaths == [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
assert !isMiniserver || hostConfig.sops.age.sshKeyPaths == hostKeyPaths;
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

    environment.etc = lib.optionalAttrs (hostConfig.appliance.rootStorage == "nvme-btrfs") {
      "nanoserver-root-reset.sh".text = rootResetScript;
      "nanoserver-root-blank-hook.sh".text = rootBlankPostCreateHook;
    };
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
        machine.succeed("printf stale > /mnt/root-stale && printf keep > /mnt/persist/root-persist")
        machine.succeed("umount -Rv /mnt")
        ${lib.replaceStrings [ "\n" ] [ "\n  " ] (lib.removeSuffix "\n" rootResetTestScript)}
        machine.succeed("echo yes | ${lib.getExe nodes.machine.system.build.destroy}")
        machine.succeed("echo yes | ${lib.getExe nodes.machine.system.build.destroy}")
    '';
}
