{ lib, pkgs, self }:
let
  slotA = self.nixosConfigurations.nanoserver-01-update-v2-a;
  slotB = self.nixosConfigurations.nanoserver-01-update-v2-b;
  slotAStoreTransfer = builtins.readFile (
    slotA.config.environment.etc."sysupdate.nanoserver.d/10-store.transfer".source
  );
  slotARegistrationTransfer = builtins.readFile (
    slotA.config.environment.etc."sysupdate.nanoserver.d/20-registration.transfer".source
  );
  slotAUkiTransfer = builtins.readFile (
    slotA.config.environment.etc."sysupdate.nanoserver.d/80-uki-boot-a.transfer".source
  );
  slotBUkiTransfer = builtins.readFile (
    slotB.config.environment.etc."sysupdate.nanoserver.d/81-uki-boot-b.transfer".source
  );
in
assert builtins.elem "appliance" slotA.config.hostSpec.enabledFeatures;
assert builtins.elem "appliance" slotB.config.hostSpec.enabledFeatures;
assert
  slotA.config.appliance.update.sourceUrl
  == "https://github.com/RogerNavelsaker/nix-config/releases/latest/download";
assert slotB.config.appliance.update.sourceUrl == slotA.config.appliance.update.sourceUrl;
assert lib.any (package: package.name == "appliance-update") slotA.config.environment.systemPackages;
assert lib.any (package: package.name == "appliance-update") slotB.config.environment.systemPackages;
assert builtins.elem "appliance-disko" slotA.config.hostSpec.enabledFeatures;
assert builtins.elem "appliance-disko" slotB.config.hostSpec.enabledFeatures;
assert !slotA.config.nix.enable;
assert !slotA.config.system.switch.enable;
assert !slotA.config.users.mutableUsers;
assert slotA.config.sops.useSystemdActivation;
assert slotA.config.sops.age.sshKeyPaths == [ "/persist/etc/ssh/ssh_host_ed25519_key" ];
assert builtins.elem "local-fs.target" slotA.config.systemd.services.sops-install-secrets.after;
assert builtins.elem "/etc/ssh/ssh_host_ed25519_key" (
  builtins.map (file: file.file) slotA.config.environment.persistence."/persist".files
);
assert slotA.config.fileSystems."/persist".neededForBoot;
assert !slotA.config.disko.enableConfig;
assert
  builtins.map (swap: swap.device) slotA.config.swapDevices == [
    "/dev/disk/by-partuuid/${slotA.config.appliance.btrfs.swapPartUuidA}"
    "/dev/disk/by-partuuid/${slotA.config.appliance.btrfs.swapPartUuidB}"
  ];
assert builtins.all (
  swap: swap.priority == 10 && !swap.randomEncryption.enable
) slotA.config.swapDevices;
assert slotA.config.boot.initrd.systemd.enable;
assert slotA.config.networking.useNetworkd;
assert slotA.config.appliance.rootSlot == "a";
assert slotB.config.appliance.rootSlot == "b";
assert slotA.config.fileSystems."/".device == "tmpfs";
assert slotB.config.fileSystems."/".device == "tmpfs";
assert slotA.config.fileSystems."/nix/store".device == slotA.config.appliance.btrfs.rootMemberA;
assert slotB.config.fileSystems."/nix/store".device == slotB.config.appliance.btrfs.rootMemberB;
assert lib.hasInfix "device_scan_wait_seconds=10" (
  slotA.config.boot.initrd.systemd.services."nanoserver-btrfs-device-scan".script
);
assert lib.hasInfix "device_scan_wait_seconds=10" (
  slotB.config.boot.initrd.systemd.services."nanoserver-btrfs-device-scan".script
);
assert lib.hasInfix "Type=url-tar" slotAStoreTransfer;
assert lib.hasInfix "Verify=yes" slotAStoreTransfer;
assert lib.hasInfix "Type=url-file" slotARegistrationTransfer;
assert lib.hasInfix "nanoserver-store_@v.registration" slotARegistrationTransfer;
assert lib.hasInfix "Verify=yes" slotARegistrationTransfer;
assert builtins.elem "timers.target" slotA.config.systemd.timers.systemd-sysupdate.wantedBy;
assert !slotA.config.systemd.sysupdate.reboot.enable;
assert lib.hasInfix "MatchPattern=nanoserver-root_@v+@l-@d.efi\nMatchPattern=nanoserver-root_@v.efi" slotAUkiTransfer;
assert lib.hasInfix "MatchPattern=nanoserver-root_@v+@l-@d.efi\nMatchPattern=nanoserver-root_@v.efi" slotBUkiTransfer;
assert lib.hasInfix "Type=url-file" slotAUkiTransfer;
assert lib.hasInfix "Verify=yes" slotAUkiTransfer;
assert builtins.elem
  "subvol=${slotA.config.appliance.storeName}_${slotA.config.appliance.rootVersion}"
  slotA.config.fileSystems."/nix/store".options;
assert builtins.elem
  "subvol=${slotB.config.appliance.storeName}_${slotB.config.appliance.rootVersion}"
  slotB.config.fileSystems."/nix/store".options;
assert
  slotA.config.appliance.btrfs.rootMemberA
  == "/dev/disk/by-partuuid/${slotA.config.appliance.btrfs.rootPartUuidA}";
assert
  slotB.config.appliance.btrfs.rootMemberB
  == "/dev/disk/by-partuuid/${slotB.config.appliance.btrfs.rootPartUuidB}";
assert
  slotA.config.fileSystems."/run/nanoserver-rootpool".device
  == slotA.config.appliance.btrfs.rootMemberA;
assert
  slotB.config.fileSystems."/run/nanoserver-rootpool".device
  == slotB.config.appliance.btrfs.rootMemberB;
assert builtins.elem "nanoserver.slot=a" slotA.config.boot.kernelParams;
assert builtins.elem "nanoserver.slot=b" slotB.config.boot.kernelParams;
assert slotA.config.system.boot.loader.ukiFile == slotB.config.system.boot.loader.ukiFile;
assert builtins.any (
  entry: builtins.match ".*--path=/boot good$" entry != null
) slotA.config.systemd.services.systemd-bless-boot.serviceConfig.ExecStart;
assert builtins.any (
  entry: builtins.match ".*--path=/boot-b good$" entry != null
) slotB.config.systemd.services.systemd-bless-boot.serviceConfig.ExecStart;
assert slotA.config.system.build.uki != slotB.config.system.build.uki;
assert builtins.elem slotB.config.system.build.toplevel
  slotA.config.appliance.storeClosureToplevels;
pkgs.runCommand "nanoserver-slot-uki-evaluation" { } ''
  touch "$out"
''
