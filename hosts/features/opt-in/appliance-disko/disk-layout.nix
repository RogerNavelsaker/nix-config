{ config, lib, ... }:
let
  storeSubvolume = "${config.appliance.storeName}_${config.appliance.rootVersion}";
  root = config.appliance.btrfs;
  inherit (config.appliance) devices;
  inherit (config.appliance.update) rootPoolPath;
  dataMemberA = "/dev/disk/by-partuuid/${root.dataPartUuidA}";
  rootSubvolumes =
    if config.appliance.rootStorage == "nvme-btrfs" then
      {
        "@root" = {
          mountpoint = "/";
          mountOptions = [
            "degraded"
            "compress=zstd:1"
            "noatime"
          ];
        };
        "@root-blank" = { };
      }
    else
      { };
  rootBlankPostCreateHook =
    if config.appliance.rootStorage == "nvme-btrfs" then
      ''
        set -euo pipefail
        root_blank_mount=$(mktemp -d)
        mounted=0
        cleanup() {
          if [ "$mounted" -eq 1 ]; then umount "$root_blank_mount"; fi
          rmdir "$root_blank_mount"
        }
        trap cleanup EXIT
        mount -t btrfs -o degraded,subvolid=5 "$device" "$root_blank_mount"
        mounted=1
        blank="$root_blank_mount/@root-blank"
        blank_ro=$(btrfs property get -ts "$blank" ro)
        if ! (
          set +f
          shopt -s nullglob dotglob
          blank_entries=("$blank"/*)
          [ "''${#blank_entries[@]}" -eq 0 ]
        ); then
          echo "Refusing non-empty @root-blank template" >&2
          exit 1
        fi
        if [ "$blank_ro" != "ro=true" ]; then
          btrfs property set -ts "$blank" ro true
        fi
      ''
    else
      "";
in
{
  disko.devices.disk = {
    usbA = {
      type = "disk";
      device = devices.usbA;
      destroy = true;
      content = {
        type = "gpt";
        partitions = {
          esp = {
            name = "1";
            uuid = devices.espPartUuidA;
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = config.appliance.update.espAPath;
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            name = "2";
            uuid = root.rootPartUuidA;
            size = "100%";
            type = "8300";
            content = null;
          };
        };
      };
    };

    usbB = {
      type = "disk";
      device = devices.usbB;
      destroy = true;
      content = {
        type = "gpt";
        partitions = {
          esp = {
            name = "1";
            uuid = devices.espPartUuidB;
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = config.appliance.update.espBPath;
              mountOptions = [ "umask=0077" ];
            };
          };
          root = {
            name = "2";
            uuid = root.rootPartUuidB;
            size = "100%";
            type = "8300";
            content = {
              type = "btrfs";
              extraArgs = [
                "-d"
                "raid1"
                "-m"
                "raid1"
                "-U"
                root.rootUuid
                root.rootMemberA
              ];
              mountpoint = rootPoolPath;
              mountOptions = [
                "degraded"
                "noatime"
                "subvolid=5"
              ];
              subvolumes.${storeSubvolume} = {
                name = storeSubvolume;
                mountpoint = "/nix/store";
                mountOptions = [
                  "degraded"
                  "compress=zstd:1"
                  "noatime"
                ] ++ lib.optional config.appliance.storeReadOnly "ro";
              };
            };
          };
        };
      };
    };

    nvmeA = {
      type = "disk";
      device = devices.nvmeA;
      destroy = true;
      content = {
        type = "gpt";
        partitions = {
          data = {
            name = "1";
            uuid = root.dataPartUuidA;
            end = "-8G";
            priority = 1000;
            type = "8300";
            content = null;
          };
          swap = {
            name = "2";
            uuid = root.swapPartUuidA;
            size = "8G";
            priority = 1100;
            type = "8200";
            content = {
              type = "swap";
              randomEncryption = false;
              discardPolicy = "once";
              priority = 10;
            };
          };
        };
      };
    };

    nvmeB = {
      type = "disk";
      device = devices.nvmeB;
      destroy = true;
      content = {
        type = "gpt";
        partitions = {
          data = {
            name = "1";
            uuid = root.dataPartUuidB;
            end = "-8G";
            priority = 1000;
            type = "8300";
            content = {
              type = "btrfs";
              extraArgs = [
                "-d"
                "raid1"
                "-m"
                "raid1"
                "-U"
                root.dataUuid
                dataMemberA
              ];
              subvolumes = {
                "@persist" = {
                  mountpoint = "/persist";
                  mountOptions = [
                    "compress=zstd:1"
                    "noatime"
                    "degraded"
                  ];
                };
              }
              // rootSubvolumes;
              postCreateHook = rootBlankPostCreateHook;
            };
          };
          swap = {
            name = "2";
            uuid = root.swapPartUuidB;
            size = "8G";
            priority = 1100;
            type = "8200";
            content = {
              type = "swap";
              randomEncryption = false;
              discardPolicy = "once";
              priority = 10;
            };
          };
        };
      };
    };
  };
}
