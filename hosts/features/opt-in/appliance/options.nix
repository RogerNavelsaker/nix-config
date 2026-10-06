{ config, lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.appliance = {
    name = mkOption {
      type = types.strMatching "[a-z][a-z0-9-]*";
      default =
        if config.networking.hostName == null then "appliance" else config.networking.hostName;
      description = "Stable role name used for appliance update and boot artifacts; defaults to the host name.";
    };

    rootName = mkOption {
      type = types.str;
      default = "${config.appliance.name}-root";
      description = "Prefix for slot-specific UKI artifacts.";
    };

    storeName = mkOption {
      type = types.str;
      default = "${config.appliance.name}-store";
      description = "Prefix for versioned Nix store subvolumes and their update artifacts.";
    };

    rootVersion = mkOption {
      type = types.str;
      default = "1";
      description = "Version of the appliance root payload and matching UKIs.";
    };

    rootSlot = mkOption {
      type = types.enum [
        "a"
        "b"
      ];
      default = "a";
      description = "USB root member selected by this system's UKI.";
    };

    peerUki = mkOption {
      type = types.nullOr types.package;
      default = null;
      internal = true;
      description = "The other slot's UKI, installed on its matching ESP during initial provisioning.";
    };

    storeClosureToplevels = mkOption {
      type = types.listOf types.package;
      default = [ ];
      internal = true;
      description = "Additional slot-specific system closures included in the shared versioned root payload.";
    };

    devices = {
      usbA = mkOption {
        type = types.str;
        description = "Stable block-device path for USB slot A.";
      };
      usbB = mkOption {
        type = types.str;
        description = "Stable block-device path for USB slot B.";
      };
      nvmeA = mkOption {
        type = types.str;
        description = "Stable block-device path for the first mirrored NVMe data disk.";
      };
      nvmeB = mkOption {
        type = types.str;
        description = "Stable block-device path for the second mirrored NVMe data disk.";
      };
      espPartUuidA = mkOption {
        type = types.str;
        description = "GPT PARTUUID for USB-A's ESP.";
      };
      espPartUuidB = mkOption {
        type = types.str;
        description = "GPT PARTUUID for USB-B's ESP.";
      };
    };

    btrfs = {
      rootUuid = mkOption {
        type = types.str;
        description = "Btrfs UUID for the mirrored USB root filesystem.";
      };
      rootPartUuidA = mkOption {
        type = types.str;
        description = "GPT PARTUUID for USB-A's Btrfs root member.";
      };
      rootPartUuidB = mkOption {
        type = types.str;
        description = "GPT PARTUUID for USB-B's Btrfs root member.";
      };
      rootMemberA = mkOption {
        type = types.str;
        default = "/dev/disk/by-partuuid/${config.appliance.btrfs.rootPartUuidA}";
        description = "Block-device path for USB root mirror member A.";
      };
      rootMemberB = mkOption {
        type = types.str;
        default = "/dev/disk/by-partuuid/${config.appliance.btrfs.rootPartUuidB}";
        description = "Block-device path for USB root mirror member B.";
      };
      dataUuid = mkOption {
        type = types.str;
        description = "Btrfs UUID for the mirrored NVMe data filesystem.";
      };
      dataPartUuidA = mkOption {
        type = types.str;
        description = "GPT PARTUUID for NVMe-A's Btrfs data member.";
      };
      dataPartUuidB = mkOption {
        type = types.str;
        description = "GPT PARTUUID for NVMe-B's Btrfs data member.";
      };
      swapPartUuidA = mkOption {
        type = types.str;
        description = "GPT PARTUUID for NVMe-A swap.";
      };
      swapPartUuidB = mkOption {
        type = types.str;
        description = "GPT PARTUUID for NVMe-B swap.";
      };
    };

    update = {
      sourceUrl = mkOption {
        type = types.str;
        default = "https://github.com/RogerNavelsaker/nix-config/releases/latest/download";
        description = "HTTPS base URL serving this appliance's versioned update files and signed SHA256SUMS manifest.";
      };
      espAPath = mkOption {
        type = types.str;
        default = "/boot";
        description = "Mount point of USB-A's ESP for systemd-sysupdate.";
      };
      espBPath = mkOption {
        type = types.str;
        default = "/boot-b";
        description = "Mount point of USB-B's ESP for systemd-sysupdate.";
      };
      rootPoolPath = mkOption {
        type = types.str;
        default = "/run/${config.appliance.name}-rootpool";
        description = "Mount point of the top-level Btrfs root pool.";
      };
    };
  };
}
