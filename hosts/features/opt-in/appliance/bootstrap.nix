{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.appliance.bootstrap;
  inherit (config.appliance) name storeName rootVersion;
  inherit (config.appliance.update) rootPoolPath espAPath espBPath;
  inherit (config.appliance.btrfs)
    rootUuid
    rootMemberA
    rootMemberB
    dataUuid
    dataPartUuidA
    dataPartUuidB
    rootPartUuidA
    rootPartUuidB
    ;
  inherit (config.appliance.devices) espPartUuidA espPartUuidB;
  finalStoreSubvolume = "${cfg.finalStoreName}_${cfg.finalRootVersion}";
  finalRegistrationPath = "/persist/${name}/store-registrations/${finalStoreSubvolume}.registration";
  bootstrapUkiFile = config.system.boot.loader.ukiFile;
  installApplianceImage = ''
    set -euo pipefail

    root_pool=${lib.escapeShellArg rootPoolPath}
    esp_a=${lib.escapeShellArg espAPath}
    esp_b=${lib.escapeShellArg espBPath}
    persist=/persist
    store_tarball=${lib.escapeShellArg cfg.finalStoreTarball}
    registration=${lib.escapeShellArg cfg.finalStoreRegistration}
    slot_a_uki=${lib.escapeShellArg cfg.finalSlotAuki}
    slot_b_uki=${lib.escapeShellArg cfg.finalSlotBuki}
    final_store_subvolume=${lib.escapeShellArg finalStoreSubvolume}
    final_toplevel_name=${lib.escapeShellArg cfg.finalToplevelName}
    final_store="$root_pool/$final_store_subvolume"
    staging_store="$root_pool/$final_store_subvolume.bootstrap-staging"
    registration_path=${lib.escapeShellArg finalRegistrationPath}
    bootstrap_uki_file=${lib.escapeShellArg bootstrapUkiFile}
    slot_a_uki_file=${lib.escapeShellArg cfg.finalSlotAukiFile}
    slot_b_uki_file=${lib.escapeShellArg cfg.finalSlotBukiFile}

    for mountpoint in "$root_pool" "$esp_a" "$esp_b" "$persist"; do
      ${pkgs.util-linux}/bin/mountpoint -q "$mountpoint" || {
        echo "Bootstrap image staging requires mounted filesystem: $mountpoint" >&2
        exit 1
      }
    done
    [ "$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE --target "$root_pool" | ${pkgs.coreutils}/bin/tail -n 1)" = btrfs ] || {
      echo "Bootstrap root pool is not mounted as Btrfs." >&2
      exit 1
    }
    [ "$(${pkgs.util-linux}/bin/findmnt -n -o UUID --target "$root_pool" | ${pkgs.coreutils}/bin/tail -n 1)" = ${lib.escapeShellArg rootUuid} ] || {
      echo "USB root pool UUID does not match the configured Miniserver filesystem." >&2
      exit 1
    }
    [ "$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE --target "$persist")" = btrfs ] || {
      echo "Persistent storage is not mounted as Btrfs." >&2
      exit 1
    }
    [ "$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE --target "$esp_a")" = vfat ] || {
      echo "USB-A ESP is not mounted as FAT." >&2
      exit 1
    }
    [ "$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE --target "$esp_b")" = vfat ] || {
      echo "USB-B ESP is not mounted as FAT." >&2
      exit 1
    }

    for check in "$esp_a ${espPartUuidA}" "$esp_b ${espPartUuidB}"; do
      set -- $check
      mountpoint=$1
      expected_partuuid=$2
      source=$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE --target "$mountpoint")
      actual_partuuid=$(${pkgs.util-linux}/bin/blkid -s PARTUUID -o value "$source")
      [ "$actual_partuuid" = "$expected_partuuid" ] || {
        echo "Unexpected ESP identity for $mountpoint; refusing bootstrap image staging." >&2
        exit 1
      }
    done

    for check in \
      "${rootMemberA} ${rootPartUuidA}" \
      "${rootMemberB} ${rootPartUuidB}" \
      "/dev/disk/by-partuuid/${dataPartUuidA} ${dataPartUuidA}" \
      "/dev/disk/by-partuuid/${dataPartUuidB} ${dataPartUuidB}"; do
      set -- $check
      device=$1
      expected_partuuid=$2
      actual_partuuid=$(${pkgs.util-linux}/bin/blkid -s PARTUUID -o value "$device")
      [ "$actual_partuuid" = "$expected_partuuid" ] || {
        echo "Unexpected partition identity for $device; refusing bootstrap image staging." >&2
        exit 1
      }
    done

    for member in ${lib.escapeShellArg rootMemberA} ${lib.escapeShellArg rootMemberB}; do
      [ "$(${pkgs.util-linux}/bin/blkid -s UUID -o value "$member")" = ${lib.escapeShellArg rootUuid} ] || {
        echo "Configured USB root member does not match the expected Btrfs UUID." >&2
        exit 1
      }
    done
    [ "$(${pkgs.util-linux}/bin/findmnt -n -o UUID --target "$persist")" = ${lib.escapeShellArg dataUuid} ] || {
      echo "Persistent filesystem UUID does not match the configured Miniserver pool." >&2
      exit 1
    }

    for artifact in "$store_tarball" "$registration" "$slot_a_uki" "$slot_b_uki"; do
      [ -s "$artifact" ] || {
        echo "Missing bootstrap image artifact: $artifact" >&2
        exit 1
      }
    done


    ${pkgs.coreutils}/bin/mkdir -p "$root_pool" "$esp_a/EFI/Linux" "$esp_b/EFI/Linux" "$esp_a/loader" "$esp_b/loader" "$(dirname "$registration_path")"
    if [ -e "$final_store" ]; then
      ${pkgs.btrfs-progs}/bin/btrfs subvolume show "$final_store" >/dev/null || {
        echo "Final appliance store path exists but is not a Btrfs subvolume." >&2
        exit 1
      }
      [ "$(${pkgs.btrfs-progs}/bin/btrfs property get -ts "$final_store" ro)" = "ro=true" ] || {
        echo "Existing final appliance store subvolume is not read-only." >&2
        exit 1
      }
      [ -e "$final_store/$final_toplevel_name" ] || {
        echo "Existing final appliance store is missing its expected toplevel." >&2
        exit 1
      }
    else
      expected_bytes=$(${pkgs.xz}/bin/xz --robot --list --verbose "$store_tarball" \
        | ${pkgs.gawk}/bin/awk '$1 == "totals" { print $5 }')
      available_bytes=$(${pkgs.coreutils}/bin/df -B1 --output=avail "$root_pool" \
        | ${pkgs.coreutils}/bin/tail -n 1 \
        | ${pkgs.coreutils}/bin/tr -d ' ')
      case "$expected_bytes:$available_bytes" in
        *[!0-9:]*|:*|*:) echo "Could not determine bootstrap image free-space requirement." >&2; exit 1 ;;
      esac
      required_bytes=$((expected_bytes + expected_bytes / 10 + 1073741824))
      [ "$available_bytes" -ge "$required_bytes" ] || {
        echo "Insufficient USB root-pool space for the final appliance image." >&2
        exit 1
      }
      [ ! -e "$staging_store" ] || {
        echo "A prior bootstrap staging subvolume exists; refusing to overwrite it." >&2
        exit 1
      }
      ${pkgs.btrfs-progs}/bin/btrfs subvolume create "$staging_store"
      ${pkgs.xz}/bin/xz -dc "$store_tarball" \
        | ${pkgs.gnutar}/bin/tar -C "$staging_store" -xf -
      [ -e "$staging_store/$final_toplevel_name" ] || {
        echo "Final store archive is missing the configured toplevel." >&2
        exit 1
      }
      ${pkgs.btrfs-progs}/bin/btrfs property set -ts "$staging_store" ro true
      ${pkgs.coreutils}/bin/mv "$staging_store" "$final_store"
    fi

    registration_tmp="$registration_path.bootstrap-staging"
    ${pkgs.coreutils}/bin/install -m 0644 "$registration" "$registration_tmp"
    ${pkgs.coreutils}/bin/mv -f "$registration_tmp" "$registration_path"
    ${pkgs.coreutils}/bin/install -m 0644 "$slot_a_uki" "$esp_a/EFI/Linux/.$slot_a_uki_file.bootstrap-staging"
    ${pkgs.coreutils}/bin/mv -f "$esp_a/EFI/Linux/.$slot_a_uki_file.bootstrap-staging" "$esp_a/EFI/Linux/$slot_a_uki_file"
    ${pkgs.coreutils}/bin/install -m 0644 "$slot_b_uki" "$esp_b/EFI/Linux/.$slot_b_uki_file.bootstrap-staging"
    ${pkgs.coreutils}/bin/mv -f "$esp_b/EFI/Linux/.$slot_b_uki_file.bootstrap-staging" "$esp_b/EFI/Linux/$slot_b_uki_file"
    ${pkgs.diffutils}/bin/cmp -s "$slot_a_uki" "$esp_a/EFI/Linux/$slot_a_uki_file"
    ${pkgs.diffutils}/bin/cmp -s "$slot_b_uki" "$esp_b/EFI/Linux/$slot_b_uki_file"
    ${pkgs.diffutils}/bin/cmp -s "$registration" "$registration_path"

    if [ "$bootstrap_uki_file" = "$slot_a_uki_file" ] || [ "$bootstrap_uki_file" = "$slot_b_uki_file" ]; then
      echo "Bootstrap and final appliance UKIs unexpectedly share a filename." >&2
      exit 1
    fi
    ${pkgs.coreutils}/bin/rm -f "$esp_a/EFI/Linux/$bootstrap_uki_file" "$esp_b/EFI/Linux/$bootstrap_uki_file"
    printf 'default %s\ntimeout 3\neditor no\n' "$slot_a_uki_file" > "$esp_a/loader/loader.conf"
    printf 'default %s\ntimeout 3\neditor no\n' "$slot_b_uki_file" > "$esp_b/loader/loader.conf"
    ${pkgs.coreutils}/bin/sync
  '';
  stageScript = pkgs.writeShellScript "${name}-bootstrap-stage" installApplianceImage;
  installStageScript = pkgs.writeShellScript "${name}-bootstrap-stage-install" ''
    set -euo pipefail
    root_pool=${lib.escapeShellArg rootPoolPath}
    mounted_root_pool=0
    if ! ${pkgs.util-linux}/bin/mountpoint -q "$root_pool"; then
      ${pkgs.coreutils}/bin/mkdir -p "$root_pool"
      ${pkgs.util-linux}/bin/mount -t btrfs -o degraded,subvolid=5 ${lib.escapeShellArg rootMemberA} "$root_pool"
      mounted_root_pool=1
    fi
    cleanup_root_pool() {
      if [ "$mounted_root_pool" -eq 1 ]; then
        ${pkgs.util-linux}/bin/umount "$root_pool"
      fi
    }
    trap cleanup_root_pool EXIT
    ${stageScript}
  '';
in
{
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      systemd.sysupdate.enable = lib.mkForce false;
      assertions = [
        {
          assertion = builtins.all (value: value != null) [
            cfg.finalStoreName
            cfg.finalRootVersion
            cfg.finalToplevelName
            cfg.finalStoreTarball
            cfg.finalStoreRegistration
            cfg.finalSlotAuki
            cfg.finalSlotAukiFile
            cfg.finalSlotBuki
            cfg.finalSlotBukiFile
          ];
          message = "appliance.bootstrap.enable requires complete final appliance image artifacts.";
        }
        {
          assertion = cfg.finalStoreName != storeName || cfg.finalRootVersion != rootVersion;
          message = "The bootstrap store subvolume must not collide with the final appliance store subvolume.";
        }
        {
          assertion = builtins.all (filename: builtins.match "^[A-Za-z0-9+._-]+$" filename != null) [
            cfg.finalSlotAukiFile
            cfg.finalSlotBukiFile
            bootstrapUkiFile
          ];
          message = "Bootstrap and final UKI filenames may only contain safe EFI filename characters.";
        }
      ];
      system.extraDependencies = [
        cfg.finalStoreTarball
        cfg.finalStoreRegistration
        cfg.finalSlotAuki
        cfg.finalSlotBuki
        stageScript
      ];
      system.build.applianceBootstrapStage = stageScript;
      boot.loader.systemd-boot.extraInstallCommands = lib.mkAfter ''
        if [ "''${NIXOS_INSTALL_BOOTLOADER:-}" = "1" ]; then
          ${installStageScript}
        fi
      '';
    })
    (lib.mkIf (config.appliance.bootstrapStoreSubvolume != null) {
      systemd.services."${name}-bootstrap-store-cleanup" = {
        description = "Remove the temporary ${name} bootstrap store after appliance boot";
        wantedBy = [ "multi-user.target" ];
        after = [ "local-fs.target" ];
        before = [ "systemd-sysupdate.service" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          RequiresMountsFor = [ rootPoolPath ];
        };
        path = [
          pkgs.btrfs-progs
          pkgs.coreutils
          pkgs.util-linux
        ];
        script = ''
          set -euo pipefail
          ${pkgs.util-linux}/bin/mountpoint -q ${lib.escapeShellArg rootPoolPath}
          [ "$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE --target ${lib.escapeShellArg rootPoolPath})" = btrfs ]
          bootstrap_store=${lib.escapeShellArg "${rootPoolPath}/${config.appliance.bootstrapStoreSubvolume}"}
          [ "$bootstrap_store" != ${lib.escapeShellArg "${rootPoolPath}/${storeName}_${rootVersion}"} ]
          if [ -e "$bootstrap_store" ]; then
            ${pkgs.btrfs-progs}/bin/btrfs subvolume show "$bootstrap_store" >/dev/null
            ${pkgs.btrfs-progs}/bin/btrfs subvolume delete "$bootstrap_store"
            ${pkgs.btrfs-progs}/bin/btrfs filesystem sync ${lib.escapeShellArg rootPoolPath}
          fi
        '';
      };
    })
  ];
}
