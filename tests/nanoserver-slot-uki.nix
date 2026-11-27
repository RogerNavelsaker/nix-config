{
  lib,
  pkgs,
  self,
}:
let
  slotA = self.nixosConfigurations.nanoserver-01-update-v3-a;
  slotB = self.nixosConfigurations.nanoserver-01-update-v3-b;
  slotV4A = self.nixosConfigurations.nanoserver-01-update-v4-a;
  slotV4B = self.nixosConfigurations.nanoserver-01-update-v4-b;
  slotAStoreTransfer =
    builtins.readFile
      slotA.config.environment.etc."sysupdate.nanoserver.d/10-store.transfer".source;
  slotARegistrationTransfer =
    builtins.readFile
      slotA.config.environment.etc."sysupdate.nanoserver.d/20-registration.transfer".source;
  slotAUkiTransfer =
    builtins.readFile
      slotA.config.environment.etc."sysupdate.nanoserver.d/80-uki-boot-a.transfer".source;
  slotBUkiTransfer =
    builtins.readFile
      slotB.config.environment.etc."sysupdate.nanoserver.d/81-uki-boot-b.transfer".source;
  slotAUpdatePackage = builtins.head (
    builtins.filter (
      package: package.name == "appliance-update"
    ) slotA.config.environment.systemPackages
  );
  slotAUpdateScript = builtins.readFile "${slotAUpdatePackage}/bin/appliance-update";
  slotAUpdateUnit = slotA.config.systemd.units."systemd-sysupdate.service".text;
in
assert builtins.elem "appliance" slotA.config.hostSpec.enabledFeatures;
assert builtins.elem "appliance" slotB.config.hostSpec.enabledFeatures;
assert
  slotA.config.appliance.update.sourceUrl
  == "https://github.com/RogerNavelsaker/nix-config/releases/latest/download";
assert slotB.config.appliance.update.sourceUrl == slotA.config.appliance.update.sourceUrl;
assert lib.any (
  package: package.name == "appliance-update"
) slotA.config.environment.systemPackages;
assert lib.any (
  package: package.name == "appliance-update"
) slotB.config.environment.systemPackages;
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
assert slotA.config.appliance.rootVersion == "3";
assert slotB.config.appliance.rootVersion == "3";
assert lib.hasInfix "IMAGE_VERSION=3" slotA.config.environment.etc.os-release.text;
assert slotA.config.fileSystems."/".device == "tmpfs";
assert slotB.config.fileSystems."/".device == "tmpfs";
assert slotA.config.appliance.rootStorage == "tmpfs";
assert slotB.config.appliance.rootStorage == "tmpfs";
assert slotV4A.config.appliance.rootStorage == "nvme-btrfs";
assert slotV4B.config.appliance.rootStorage == "nvme-btrfs";
assert
  slotV4A.config.fileSystems."/".device
  == "/dev/disk/by-uuid/${slotV4A.config.appliance.btrfs.dataUuid}";
assert
  slotV4B.config.fileSystems."/".device
  == "/dev/disk/by-uuid/${slotV4B.config.appliance.btrfs.dataUuid}";
assert slotV4A.config.fileSystems."/".fsType == "btrfs";
assert slotV4B.config.fileSystems."/".fsType == "btrfs";
assert builtins.elem "subvol=@root" slotV4A.config.fileSystems."/".options;
assert builtins.elem "subvol=@persist" slotV4A.config.fileSystems."/persist".options;
assert builtins.elem "ro" slotV4A.config.fileSystems."/nix/store".options;
assert slotV4A.config.fileSystems."/nix/store".device == slotV4A.config.appliance.btrfs.rootMemberA;
assert slotV4B.config.fileSystems."/nix/store".device == slotV4B.config.appliance.btrfs.rootMemberB;
assert builtins.elem "sysroot.mount"
  slotV4A.config.boot.initrd.systemd.services."nanoserver-root-reset".before;
assert builtins.elem "sysroot.mount"
  slotV4A.config.boot.initrd.systemd.services."nanoserver-root-reset".requiredBy;
assert slotA.config.fileSystems."/nix/store".device == slotA.config.appliance.btrfs.rootMemberA;
assert slotB.config.fileSystems."/nix/store".device == slotB.config.appliance.btrfs.rootMemberB;
assert lib.hasInfix "device_scan_wait_seconds=10"
  slotA.config.boot.initrd.systemd.services."nanoserver-btrfs-device-scan".script;
assert lib.hasInfix "device_scan_wait_seconds=10"
  slotB.config.boot.initrd.systemd.services."nanoserver-btrfs-device-scan".script;
assert lib.hasInfix "Type=url-tar" slotAStoreTransfer;
assert lib.hasInfix "ProtectVersion=%A" slotAStoreTransfer;
assert lib.hasInfix "InstancesMax=2" slotAStoreTransfer;
assert lib.hasInfix "Verify=yes" slotAStoreTransfer;
assert lib.hasInfix "Type=url-file" slotARegistrationTransfer;
assert lib.hasInfix "nanoserver-store_@v.registration" slotARegistrationTransfer;
assert lib.hasInfix "ProtectVersion=%A" slotARegistrationTransfer;
assert lib.hasInfix "InstancesMax=2" slotARegistrationTransfer;
assert lib.hasInfix "Verify=yes" slotARegistrationTransfer;
assert builtins.elem "timers.target" slotA.config.systemd.timers.systemd-sysupdate.wantedBy;
assert !slotA.config.systemd.sysupdate.reboot.enable;
assert lib.hasInfix "MatchPattern=nanoserver-root_@v+@l-@d.efi\nMatchPattern=nanoserver-root_@v.efi"
  slotAUkiTransfer;
assert lib.hasInfix "MatchPattern=nanoserver-root_@v+@l-@d.efi\nMatchPattern=nanoserver-root_@v.efi"
  slotBUkiTransfer;
assert lib.hasInfix "Type=url-file" slotAUkiTransfer;
assert lib.hasInfix "MatchPattern=nanoserver-root_@v+@l-slot-a.efi" slotAUkiTransfer;
assert lib.hasInfix "ProtectVersion=%A" slotAUkiTransfer;
assert lib.hasInfix "InstancesMax=2" slotAUkiTransfer;
assert lib.hasInfix "Verify=yes" slotAUkiTransfer;
assert lib.hasInfix "MatchPattern=nanoserver-root_@v+@l-slot-b.efi" slotBUkiTransfer;
assert lib.hasInfix "ProtectVersion=%A" slotBUkiTransfer;
assert lib.hasInfix "InstancesMax=2" slotBUkiTransfer;
assert lib.hasInfix "--component=nanoserver check-new" slotAUpdateScript;
assert lib.hasInfix "--json=short list" slotAUpdateScript;
assert lib.hasInfix "--component=nanoserver update" slotAUpdateScript;
assert lib.hasInfix "--esp-path=\"$active_esp\" set-oneshot" slotAUpdateScript;
assert !(lib.hasInfix "systemctl reboot" slotAUpdateScript);
assert lib.hasInfix "--latest" slotAUpdateUnit;
assert lib.hasInfix "Type=oneshot" slotAUpdateUnit;
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
pkgs.runCommand "nanoserver-slot-uki-evaluation"
  {
    nativeBuildInputs = [ pkgs.jq ];
  }
  ''
    set -euo pipefail
    fixture="$TMPDIR/sysupdate"
    source="$fixture/source"
    target="$fixture/target"
    definitions="$fixture/definitions"
    sysupdate=${pkgs.systemd}/lib/systemd/systemd-sysupdate
    mkdir -p "$definitions" "$target/nanoserver-store_1"
    for version in 1 2; do
      mkdir -p "$source/nanoserver-store_$version"
      printf 'version %s\\n' "$version" > "$source/nanoserver-store_$version/payload"
    done
    printf 'active version 1\\n' > "$target/nanoserver-store_1/payload"

    write_transfer() {
      cat > "$definitions/10-store.transfer" <<EOF
    [Transfer]
    ProtectVersion=$1
    [Source]
    Type=directory
    Path=$source
    MatchPattern=nanoserver-store_@v
    [Target]
    Type=directory
    Path=$target
    MatchPattern=nanoserver-store_@v
    InstancesMax=2
    EOF
    }

    write_transfer 1
    candidate=$("$sysupdate" --definitions="$definitions" check-new)
    test "$candidate" = 2
    "$sysupdate" --definitions="$definitions" update "$candidate"
    test -d "$target/nanoserver-store_1"
    test -d "$target/nanoserver-store_2"

    if candidate=$("$sysupdate" --definitions="$definitions" check-new); then
      echo "expected no candidate after version 2 was staged, got $candidate" >&2
      exit 1
    fi
    listing=$("$sysupdate" --definitions="$definitions" --json=short list)
    current=$(printf '%s' "$listing" | jq -r '.current // empty')
    latest=$(printf '%s' "$listing" | jq -r '.all[0] // empty')
    test "$current" = 2
    test "$latest" = 2

    mkdir -p "$source/nanoserver-store_3"
    printf 'version 3\\n' > "$source/nanoserver-store_3/payload"
    write_transfer 1
    candidate=$("$sysupdate" --definitions="$definitions" check-new)
    test "$candidate" = 3
    "$sysupdate" --definitions="$definitions" update "$candidate"
    test -d "$target/nanoserver-store_1"
    test -d "$target/nanoserver-store_3"
    test ! -e "$target/nanoserver-store_2"

    mkdir -p "$source/nanoserver-store_4"
    printf 'version 4\\n' > "$source/nanoserver-store_4/payload"
    write_transfer 3
    candidate=$("$sysupdate" --definitions="$definitions" check-new)
    test "$candidate" = 4
    "$sysupdate" --definitions="$definitions" update "$candidate"
    test -d "$target/nanoserver-store_3"
    test -d "$target/nanoserver-store_4"
    test ! -e "$target/nanoserver-store_1"
    touch "$out"
  ''
