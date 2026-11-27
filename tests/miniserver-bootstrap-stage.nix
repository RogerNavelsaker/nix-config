{
  diskoLib,
  diskoModule,
  lib,
  pkgs,
  self,
}:
let
  bootstrap = self.nixosConfigurations.miniserver-01-bootstrap.config;
  final = self.nixosConfigurations.miniserver-01.config;
  inherit (bootstrap.appliance) btrfs devices;
  inherit (bootstrap.appliance.update) rootPoolPath;
  bootstrapStoreSubvolume = "${bootstrap.appliance.storeName}_${bootstrap.appliance.rootVersion}";
  finalStoreSubvolume = "${final.appliance.storeName}_${final.appliance.rootVersion}";
  finalStorePath = "${rootPoolPath}/${finalStoreSubvolume}";
  bootstrapStorePath = "${rootPoolPath}/${bootstrapStoreSubvolume}";
  dataDevice = "/dev/disk/by-uuid/${btrfs.dataUuid}";
  espADevice = "/dev/disk/by-partuuid/${devices.espPartUuidA}";
  espBDevice = "/dev/disk/by-partuuid/${devices.espPartUuidB}";
  finalRegistrationPath = "/persist/${final.appliance.name}/store-registrations/${finalStoreSubvolume}.registration";
  finalToplevelName = builtins.baseNameOf (toString final.system.build.toplevel);
  stageScript = bootstrap.system.build.applianceBootstrapStage;
  cleanupScript = pkgs.writeShellScript "miniserver-bootstrap-cleanup-test" (
    final.systemd.services."${final.appliance.name}-bootstrap-store-cleanup".script
  );
  diskConfig = diskoLib.testLib.prepareDiskoConfig {
    disko.devices = bootstrap.disko.devices;
  } (builtins.tail diskoLib.testLib.devices);
in
pkgs.testers.runNixOSTest {
  name = "miniserver-bootstrap-image-stage";
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
      pkgs.gnugrep
      pkgs.openssh
      pkgs.sops
      pkgs.ssh-to-age
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
      machine.succeed("mkdir -p /mnt && mount -t tmpfs -o size=128M tmpfs /mnt")
      machine.succeed("${lib.getExe nodes.machine.system.build.format}")
      machine.succeed("${lib.getExe nodes.machine.system.build.mount}")
      machine.succeed("umount -Rv /mnt")

      machine.succeed("mkdir -p ${rootPoolPath} /persist /boot /boot-b")
      machine.succeed("mount -t btrfs -o degraded,subvolid=5 ${btrfs.rootMemberA} ${rootPoolPath}")
      machine.succeed("mount -t btrfs -o degraded,subvol=@persist ${dataDevice} /persist")
      machine.succeed('mkdir -p /persist/etc/ssh && ssh-keygen -q -t ed25519 -N "" -f /persist/etc/ssh/ssh_host_ed25519_key')
      machine.succeed('test "$(stat -c %a /persist/etc/ssh/ssh_host_ed25519_key)" = 600')
      machine.succeed('test ! -e /etc/ssh/ssh_host_ed25519_key')
      machine.succeed('ssh-to-age -private-key -i /persist/etc/ssh/ssh_host_ed25519_key > /run/bootstrap-test.agekey')
      machine.succeed('recipient=$(ssh-to-age -i /persist/etc/ssh/ssh_host_ed25519_key.pub); printf "secret: disposable-bootstrap-test\\n" > /run/plain.yaml; SOPS_AGE_KEY_FILE=/run/bootstrap-test.agekey sops --encrypt --age "$recipient" --encrypted-regex "^secret$" /run/plain.yaml > /run/encrypted.yaml')
      machine.succeed('SOPS_AGE_KEY_FILE=/run/bootstrap-test.agekey sops --decrypt /run/encrypted.yaml | grep -Fx "secret: disposable-bootstrap-test"')
      machine.succeed("mount -t vfat ${espADevice} /boot")
      machine.succeed("mount -t vfat ${espBDevice} /boot-b")

      machine.succeed("btrfs subvolume show ${bootstrapStorePath}")

      machine.succeed("${stageScript}")
      machine.succeed("btrfs subvolume show ${finalStorePath}")
      machine.succeed('test "$(btrfs property get -ts ${finalStorePath} ro)" = ro=true')
      machine.succeed("test -e ${finalStorePath}/${finalToplevelName}")
      machine.succeed("cmp ${final.system.build.applianceStoreRegistration} ${finalRegistrationPath}")
      machine.succeed("cmp ${final.system.build.uki}/${final.system.boot.loader.ukiFile} /boot/EFI/Linux/${final.system.boot.loader.ukiFile}")
      machine.succeed("cmp ${self.nixosConfigurations.miniserver-01-slot-b.config.system.build.uki}/${self.nixosConfigurations.miniserver-01-slot-b.config.system.boot.loader.ukiFile} /boot-b/EFI/Linux/${self.nixosConfigurations.miniserver-01-slot-b.config.system.boot.loader.ukiFile}")
      machine.succeed("grep -Fx 'default ${final.system.boot.loader.ukiFile}' /boot/loader/loader.conf")
      machine.succeed("grep -Fx 'default ${self.nixosConfigurations.miniserver-01-slot-b.config.system.boot.loader.ukiFile}' /boot-b/loader/loader.conf")

      machine.succeed("${cleanupScript}")
      machine.succeed("test ! -e ${bootstrapStorePath}")
      machine.succeed("btrfs subvolume show ${finalStorePath}")
    '';
}
