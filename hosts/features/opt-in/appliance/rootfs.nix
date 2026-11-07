{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.appliance)
    name
    rootSlot
    rootStorage
    storeName
    ;
  inherit (config.appliance.update) rootPoolPath;
  inherit (config.appliance.btrfs)
    rootMemberA
    rootMemberB
    rootPartUuidA
    rootPartUuidB
    dataUuid
    dataPartUuidA
    dataPartUuidB
    ;
  rootDevice = if rootSlot == "a" then rootMemberA else rootMemberB;
  storeSubvolume = "${storeName}_${config.appliance.rootVersion}";

  useNvmeRoot = rootStorage == "nvme-btrfs";
  dataDevice = "/dev/disk/by-uuid/${dataUuid}";
  dataMemberA = "/dev/disk/by-partuuid/${dataPartUuidA}";
  dataMemberB = "/dev/disk/by-partuuid/${dataPartUuidB}";
  scanMembers = [
    rootMemberA
    rootMemberB
  ]
  ++ lib.optionals useNvmeRoot [
    dataMemberA
    dataMemberB
  ];
  scanMembersShell = lib.concatMapStringsSep " " (member: "\"${member}\"") scanMembers;
  missingMembersCondition = lib.concatMapStringsSep " || " (
    member: "[ ! -b \"${member}\" ]"
  ) scanMembers;
  rootPartUdevRules = pkgs.writeTextDir "lib/udev/rules.d/99zz-${name}-root-partuuid.rules" ''
    # Allow the configured Btrfs mirror members to be mounted degraded.
    SUBSYSTEM=="block", ENV{ID_PART_ENTRY_UUID}=="${rootPartUuidA}", TAG+="systemd", ENV{SYSTEMD_ALIAS}="/dev/disk/by-partuuid/${rootPartUuidA}", ENV{SYSTEMD_READY}="1"
    SUBSYSTEM=="block", ENV{ID_PART_ENTRY_UUID}=="${rootPartUuidB}", TAG+="systemd", ENV{SYSTEMD_ALIAS}="/dev/disk/by-partuuid/${rootPartUuidB}", ENV{SYSTEMD_READY}="1"
    ${lib.optionalString useNvmeRoot ''
      SUBSYSTEM=="block", ENV{ID_PART_ENTRY_UUID}=="${dataPartUuidA}", TAG+="systemd", ENV{SYSTEMD_ALIAS}="/dev/disk/by-partuuid/${dataPartUuidA}", ENV{SYSTEMD_READY}="1"
      SUBSYSTEM=="block", ENV{ID_PART_ENTRY_UUID}=="${dataPartUuidB}", TAG+="systemd", ENV{SYSTEMD_ALIAS}="/dev/disk/by-partuuid/${dataPartUuidB}", ENV{SYSTEMD_READY}="1"
    ''}
  '';
in
{
  config = {
    fileSystems = {
      "/" = lib.mkForce (
        if useNvmeRoot then
          {
            device = dataDevice;
            fsType = "btrfs";
            options = [
              "degraded"
              "compress=zstd:1"
              "noatime"
              "subvol=@root"
              "x-initrd.mount"
            ];
          }
        else
          {
            device = "tmpfs";
            fsType = "tmpfs";
            options = [
              "mode=0755"
              "size=2G"
            ];
          }
      );
      "/nix/store" = lib.mkForce {
        device = rootDevice;
        fsType = "btrfs";
        neededForBoot = true;
        options = [
          "degraded"
          "compress=zstd:1"
          "noatime"
          "ro"
          "subvol=${storeSubvolume}"
          "x-systemd.device-timeout=30s"
        ];
      };
      ${rootPoolPath} = lib.mkForce {
        device = rootDevice;
        fsType = "btrfs";
        options = [
          "degraded"
          "noatime"
          "subvolid=5"
          "x-systemd.device-timeout=30s"
        ];
      };
    };

    # The slot UKI uses its local PARTUUID; the late Udev rule overrides
    # systemd's multi-device Btrfs readiness gate for a degraded mount.
    services.udev.packages = [ rootPartUdevRules ];
    boot = {
      initrd = {
        services.udev.packages = [ rootPartUdevRules ];
        supportedFilesystems.btrfs = true;
        systemd.services."${name}-btrfs-device-scan" = {
          description = "Scan mirrored Btrfs root members before mounting the store";
          wantedBy = [ "initrd-root-device.target" ];
          before = [ "initrd-root-device.target" ];
          after = [ "systemd-udev-settle.service" ];
          requires = [ "systemd-udev-settle.service" ];
          serviceConfig.Type = "oneshot";
          path = [
            pkgs.btrfs-progs
            pkgs.coreutils
            pkgs.systemd
          ];
          script = ''
            # USB and NVMe storage can enumerate late during initrd.
            # Wait briefly for both mirrors; if one member is absent, continue degraded.
            device_scan_wait_seconds=10
            device_scan_deadline=$((SECONDS + device_scan_wait_seconds))
            while { ${missingMembersCondition}; } && [ "$SECONDS" -lt "$device_scan_deadline" ]; do
              sleep 0.1
            done
            btrfs device scan
            # Restore SYSTEMD_READY for every available mirror member.
            for member in ${scanMembersShell}; do
              [ -b "$member" ] || continue
              member_sysname=$(basename "$(readlink -f "$member")")
              udevadm trigger --action=change --sysname-match="$member_sysname"
            done
            udevadm settle
          '';
        };

        systemd.services."${name}-root-reset" = lib.mkIf useNvmeRoot {
          description = "Restore the ephemeral Btrfs root before mounting sysroot";
          after = [ "initrd-root-device.target" ];
          before = [ "sysroot.mount" ];
          requires = [ "initrd-root-device.target" ];
          requiredBy = [ "sysroot.mount" ];
          unitConfig.DefaultDependencies = false;
          serviceConfig.Type = "oneshot";
          serviceConfig.RemainAfterExit = true;
          path = [
            pkgs.btrfs-progs
            pkgs.coreutils
            pkgs.util-linux
          ];
          script = ''
            set -euo pipefail
            pool=$(mktemp -d "/run/${name}-root-reset.XXXXXX")
            mounted=0
            cleanup() {
              if [ "$mounted" -eq 1 ]; then umount "$pool"; fi
              rmdir "$pool"
            }
            trap cleanup EXIT
            mount -t btrfs -o degraded,subvolid=5 "${dataDevice}" "$pool"
            mounted=1
            blank="$pool/@root-blank"
            root="$pool/@root"
            if ! btrfs subvolume show "$blank" >/dev/null 2>&1; then
              echo "Missing provisioned @root-blank Btrfs subvolume" >&2
              exit 1
            fi
            blank_ro=$(btrfs property get -ts "$blank" ro)
            if [ "$blank_ro" != "ro=true" ]; then
              echo "Refusing to reset root from a writable @root-blank" >&2
              exit 1
            fi
            if btrfs subvolume show "$root" >/dev/null 2>&1; then
              btrfs subvolume delete "$root"
            elif [ -e "$root" ]; then
              echo "Refusing to replace non-subvolume @root" >&2
              exit 1
            fi
            btrfs subvolume snapshot "$blank" "$root"
          '';
        };
      };
      kernelParams = lib.mkAfter [
        "${name}.version=${config.appliance.rootVersion}"
        "${name}.slot=${rootSlot}"
      ];
      uki = {
        name = config.appliance.rootName;
        tries = 3;
      };
    };
  };
}
