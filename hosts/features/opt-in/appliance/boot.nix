{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.appliance.update) espAPath espBPath;
  bootMountPoint = if config.appliance.rootSlot == "a" then espAPath else espBPath;
in
{
  config = {
    fileSystems = {
      ${espAPath} = {
        device = lib.mkForce "/dev/disk/by-partuuid/${config.appliance.devices.espPartUuidA}";
        options = lib.mkForce [
          "umask=0077"
          "nofail"
          "x-systemd.device-timeout=5s"
        ];
      };
      ${espBPath} = {
        device = lib.mkForce "/dev/disk/by-partuuid/${config.appliance.devices.espPartUuidB}";
        options = lib.mkForce [
          "umask=0077"
          "nofail"
          "x-systemd.device-timeout=5s"
        ];
      };
    };

    boot = {
      loader = {
        grub.enable = false;
        systemd-boot = {
          enable = true;
          editor = false;
          configurationLimit = 3;
          extraInstallCommands = lib.optionalString (config.appliance.rootSlot == "a") ''
            ${pkgs.util-linux}/bin/findmnt --target ${espBPath} >/dev/null
            ${pkgs.coreutils}/bin/mkdir -p ${espBPath}/EFI ${espBPath}/loader ${espBPath}/EFI/Linux
            ${pkgs.coreutils}/bin/cp -a ${espAPath}/EFI/. ${espBPath}/EFI/
            ${pkgs.coreutils}/bin/cp -a ${espAPath}/loader/. ${espBPath}/loader/
            printf 'default @saved\\ntimeout 3\\neditor no\\n' > ${espAPath}/loader/loader.conf
            ${pkgs.coreutils}/bin/cp ${espAPath}/loader/loader.conf ${espBPath}/loader/loader.conf
            ${pkgs.systemd}/bin/bootctl --esp-path=${espBPath} install --no-variables
            ${lib.optionalString (config.appliance.peerUki != null) ''
              ${pkgs.coreutils}/bin/install -D -m 0644 ${config.appliance.peerUki}/${config.system.boot.loader.ukiFile} ${espBPath}/EFI/Linux/${config.system.boot.loader.ukiFile}
            ''}
          '';
        };
        timeout = 3;
        efi = {
          canTouchEfiVariables = true;
          efiSysMountPoint = bootMountPoint;
        };
      };

      initrd = {
        systemd.enable = true;
        availableKernelModules = [
          "xhci_pci"
          "usb_storage"
          "uas"
          "sd_mod"
          "virtio_pci"
          "virtio_blk"
        ];
        kernelModules = [ "btrfs" ];
      };
      kernelParams = [ "panic=10" ];
    };

    systemd.services.systemd-bless-boot.serviceConfig.ExecStart = lib.mkForce [
      ""
      "${pkgs.systemd}/lib/systemd/systemd-bless-boot --path=${bootMountPoint} good"
    ];
  };
}
