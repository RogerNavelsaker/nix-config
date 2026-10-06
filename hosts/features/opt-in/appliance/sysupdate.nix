{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.appliance) name rootName storeName;
  inherit (config.appliance.update)
    rootPoolPath
    sourceUrl
    espAPath
    espBPath
    ;
  inherit (config.appliance.btrfs) rootUuid rootMemberA rootMemberB;
  storeTransfer = pkgs.writeText "${name}-store.transfer" ''
    [Transfer]
    ProtectVersion=%A

    [Source]
    Type=url-tar
    Path=${sourceUrl}
    Verify=yes
    MatchPattern=${storeName}_@v.tar.xz

    [Target]
    Type=subvolume
    Path=${rootPoolPath}
    MatchPattern=${storeName}_@v
    InstancesMax=2
  '';

  registrationTransfer = pkgs.writeText "${name}-registration.transfer" ''
    [Transfer]
    ProtectVersion=%A

    [Source]
    Type=url-file
    Path=${sourceUrl}
    Verify=yes
    MatchPattern=${storeName}_@v.registration

    [Target]
    Type=regular-file
    Path=/persist/${name}/store-registrations
    MatchPattern=${storeName}_@v.registration
    Mode=0644
    InstancesMax=2
  '';

  mkUkiTransfer =
    transferName: espPath: slot:
    pkgs.writeText "${name}-uki-${transferName}.transfer" ''
      [Transfer]
      ProtectVersion=%A

      [Source]
      Type=url-file
      Path=${sourceUrl}
      Verify=yes
      MatchPattern=${rootName}_@v+@l-slot-${slot}.efi

      [Target]
      Type=regular-file
      Path=${espPath}/EFI/Linux
      MatchPattern=${rootName}_@v+@l-@d.efi
      MatchPattern=${rootName}_@v.efi
      PathRelativeTo=root
      Mode=0444
      TriesLeft=3
      TriesDone=0
      InstancesMax=2
    '';

  transferFiles = [
    {
      name = "sysupdate.${name}.d/10-store.transfer";
      value.source = storeTransfer;
    }
    {
      name = "sysupdate.${name}.d/20-registration.transfer";
      value.source = registrationTransfer;
    }
    {
      name = "sysupdate.${name}.d/80-uki-boot-a.transfer";
      value.source = mkUkiTransfer "slot-a" espAPath "a";
    }
    {
      name = "sysupdate.${name}.d/81-uki-boot-b.transfer";
      value.source = mkUkiTransfer "slot-b" espBPath "b";
    }
  ];

  updateScript = pkgs.writeShellScriptBin "appliance-update" ''
    set -euo pipefail

    if [ "$EUID" -ne 0 ]; then
      echo "Run with sudo." >&2
      exit 1
    fi
    if [ "$#" -ne 1 ]; then
      echo "Usage: appliance-update <new-version>" >&2
      exit 2
    fi

    version="$1"
    case "$version" in
      ""|*[!0-9]*) echo "Version must be a positive integer." >&2; exit 2 ;;
    esac
    if [ "$version" -lt 1 ]; then
      echo "Version must be positive." >&2
      exit 2
    fi

    active_version=$(${pkgs.gnused}/bin/sed -n 's/.*${name}[.]version=\([0-9][0-9]*\).*/\1/p' /proc/cmdline | ${pkgs.coreutils}/bin/head -n1)
    if [ -z "$active_version" ]; then
      echo "Cannot identify the running store version from the kernel command line." >&2
      exit 1
    fi
    active_slot=$(${pkgs.gnused}/bin/sed -n 's/.*${name}[.]slot=\([ab]\).*/\1/p' /proc/cmdline | ${pkgs.coreutils}/bin/head -n1)
    case "$active_slot" in
      a) active_esp=${espAPath} ;;
      b) active_esp=${espBPath} ;;
      *) echo "Cannot identify the running USB slot from the kernel command line." >&2; exit 1 ;;
    esac
    if [ "$version" -le "$active_version" ]; then
      echo "Refusing to install version $version over the running store version ($active_version)." >&2
      exit 1
    fi

    root_pool=${rootPoolPath}
    ${pkgs.util-linux}/bin/mountpoint -q "$root_pool" || {
      echo "Required filesystem is not mounted: $root_pool" >&2
      exit 1
    }
    [ "$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE --target "$root_pool")" = btrfs ] || {
      echo "The root pool is not mounted as Btrfs." >&2
      exit 1
    }

    for member in "${rootMemberA}" "${rootMemberB}"; do
      [ -b "$member" ] || {
        echo "Both USB root-mirror members must be present for updates." >&2
        exit 1
      }
      member_uuid=$(${pkgs.util-linux}/bin/blkid -s UUID -o value "$member" || true)
      [ "$member_uuid" = "${rootUuid}" ] || {
        echo "Both configured USB root-mirror members must match the root filesystem UUID." >&2
        exit 1
      }
    done

    filesystem_status=$(${pkgs.btrfs-progs}/bin/btrfs filesystem show "$root_pool")
    if printf '%s\n' "$filesystem_status" | ${pkgs.gnugrep}/bin/grep -q 'missing'; then
      echo "The mirrored root filesystem is degraded; refusing update." >&2
      exit 1
    fi

    for mountpoint in "${espAPath}" "${espBPath}"; do
      ${pkgs.util-linux}/bin/mountpoint -q "$mountpoint" || {
        echo "Required ESP is not mounted: $mountpoint" >&2
        exit 1
      }
    done

    ${pkgs.util-linux}/bin/mountpoint -q /persist || {
      echo "The persistent filesystem is not mounted; refusing update." >&2
      exit 1
    }
    [ "$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE --target /persist)" = btrfs ] || {
      echo "The persistent filesystem is not mounted as Btrfs." >&2
      exit 1
    }

    echo "This stages store version $version on the mirrored USB Btrfs filesystem; version $active_version remains bootable."
    read -r -p "Type 'update-$version' to continue: " confirmation
    [ "$confirmation" = "update-$version" ] || exit 1

    ${pkgs.systemd}/lib/systemd/systemd-sysupdate \
      --no-pager --component=${name} update "$version"

    new_store="$root_pool/${storeName}_$version"
    [ -d "$new_store" ] || {
      echo "systemd-sysupdate did not create the requested store subvolume." >&2
      exit 1
    }
    registration_file="/persist/${name}/store-registrations/${storeName}_$version.registration"
    [ -s "$registration_file" ] || {
      echo "systemd-sysupdate did not install the requested registration metadata." >&2
      exit 1
    }
    sync

    # The boot-loader entry ID omits the +tries-left-done boot-count suffix.
    uki_name="${rootName}_$version.efi"
    ${pkgs.systemd}/bin/bootctl --esp-path="$active_esp" set-oneshot "$uki_name"
    echo "Store version $version is staged on both ESPs; reboot when ready."
  '';
in
{
  config = {
    environment = {
      etc = builtins.listToAttrs transferFiles // {
        "systemd/import-pubring.gpg".source = ./update-signing-key.gpg;
      };
      systemPackages = [ updateScript ];
    };

    systemd = {
      sysupdate = {
        enable = true;
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
          RandomizedDelaySec = "1h";
        };
        reboot.enable = false;
      };
      services.systemd-sysupdate = {
        after = [ "persist.mount" "systemd-tmpfiles-setup.service" ];
        requires = [ "persist.mount" ];
      };
      tmpfiles.rules = [
        "d /persist/${name}/store-registrations 0755 root root -"
      ];
      services.systemd-bless-boot = {
        wantedBy = [ "multi-user.target" ];
        after = [
          "local-fs.target"
          "sops-install-secrets.service"
          "sshd.service"
        ];
        requires = [
          "sops-install-secrets.service"
          "sshd.service"
        ];
      };
    };
  };
}
