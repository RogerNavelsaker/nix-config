{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.appliance) name rootSlot storeName;
  inherit (config.appliance.update) rootPoolPath;
  inherit (config.appliance.btrfs)
    rootMemberA
    rootMemberB
    rootPartUuidA
    rootPartUuidB
    ;
  rootDevice = if rootSlot == "a" then rootMemberA else rootMemberB;
  storeSubvolume = "${storeName}_${config.appliance.rootVersion}";
  rootPartUdevRules = pkgs.writeTextDir "lib/udev/rules.d/99zz-${name}-root-partuuid.rules" ''
    # systemd's 64-btrfs.rules marks members SYSTEMD_READY=0 until all
    # mirror members are present; allow this appliance to mount degraded.
    SUBSYSTEM=="block", ENV{ID_PART_ENTRY_UUID}=="${rootPartUuidA}", TAG+="systemd", ENV{SYSTEMD_ALIAS}="/dev/disk/by-partuuid/${rootPartUuidA}", ENV{SYSTEMD_READY}="1"
    SUBSYSTEM=="block", ENV{ID_PART_ENTRY_UUID}=="${rootPartUuidB}", TAG+="systemd", ENV{SYSTEMD_ALIAS}="/dev/disk/by-partuuid/${rootPartUuidB}", ENV{SYSTEMD_READY}="1"
  '';
in
{
  config = {
    fileSystems = {
      "/" = lib.mkForce {
        device = "tmpfs";
        fsType = "tmpfs";
        options = [
          "mode=0755"
          "size=2G"
        ];
      };
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
            # USB storage can enumerate after the first udev settle during initrd.
            # Give both mirror members a bounded window to appear before scanning;
            # if one is genuinely absent, continue with the intended degraded boot.
            device_scan_wait_seconds=10
            device_scan_deadline=$((SECONDS + device_scan_wait_seconds))
            while { [ ! -b "${rootMemberA}" ] || [ ! -b "${rootMemberB}" ]; } && [ "$SECONDS" -lt "$device_scan_deadline" ]; do
              sleep 0.1
            done
            btrfs device scan
            # Reprocess each available member after the Btrfs scan. The late
            # Udev rule restores SYSTEMD_READY for the intended degraded mount.
            for member in "${rootMemberA}" "${rootMemberB}"; do
              [ -b "$member" ] || continue
              member_sysname=$(basename "$(readlink -f "$member")")
              udevadm trigger --action=change --sysname-match="$member_sysname"
            done
            udevadm settle
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
