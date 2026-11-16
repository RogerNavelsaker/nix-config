{ pkgs }:
let
  inherit (pkgs) lib;

  makeEspImage =
    {
      id,
      diskGuid,
      partGuid,
      uki,
      systemd,
    }:
    pkgs.runCommand "bcachefs-${id}-integrated-esp.img"
      {
        nativeBuildInputs = [
          pkgs.gptfdisk
          pkgs.mtools
        ];
      }
      ''
        truncate -s 256M "$out"
        ${pkgs.gptfdisk}/bin/sgdisk \
          --clear \
          --disk-guid=${diskGuid} \
          --new=1:2048:524254 \
          --partition-guid=1:${partGuid} \
          --typecode=1:EF00 \
          "$out"
        ${pkgs.mtools}/bin/mformat -i "$out@@1048576" -F -v USBESP ::
        ${pkgs.mtools}/bin/mmd -i "$out@@1048576" ::/EFI
        ${pkgs.mtools}/bin/mmd -i "$out@@1048576" ::/EFI/BOOT
        ${pkgs.mtools}/bin/mmd -i "$out@@1048576" ::/EFI/Linux
        ${pkgs.mtools}/bin/mcopy -i "$out@@1048576" \
          "${systemd}/lib/systemd/boot/efi/systemd-bootx64.efi" \
          ::/EFI/BOOT/BOOTX64.EFI
        ${pkgs.mtools}/bin/mcopy -i "$out@@1048576" "${uki}" ::/EFI/Linux/${id}.efi
      '';

  rootReset = pkgs: {
    boot.initrd.supportedFilesystems.bcachefs = true;
    boot.initrd.systemd.services.bcachefs-root-reset = {
      description = "Recreate the disposable Bcachefs root before switch-root";
      after = [
        "sysroot.mount"
        "sysroot-nix-store.mount"
      ];
      before = [
        "initrd-nixos-activation.service"
        "initrd-switch-root.target"
      ];
      requires = [ "sysroot.mount" ];
      requiredBy = [ "initrd-nixos-activation.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig.Type = "oneshot";
      path = [
        pkgs.bcachefs-tools
        pkgs.coreutils
        pkgs.systemd
        pkgs.util-linux
      ];
      script = ''
        if [ -e /sysroot/nix/prototype-interrupt-reset-once ]; then
          rm /sysroot/nix/prototype-interrupt-reset-once
          if [ -e /sysroot/root ]; then
            bcachefs subvolume delete /sysroot/root
          fi
          reboot -f
          exit 1
        fi
        if [ ! -e /sysroot/root-blank ]; then
          if [ ! -e /sysroot/root ]; then
            bcachefs subvolume create /sysroot/root
          fi
          if [ ! -e /sysroot/nix ]; then
            bcachefs subvolume create /sysroot/nix
          fi
          bcachefs subvolume snapshot --read-only /sysroot/root /sysroot/root-blank
        fi
        if [ -e /sysroot/root ]; then
          bcachefs subvolume delete /sysroot/root
        fi
        bcachefs subvolume snapshot --rw /sysroot/root-blank /sysroot/root
        mkdir -p /sysroot/root/nix /sysroot/root/run /sysroot/root/tmp
        mount --rbind /sysroot/run /sysroot/root/run
        mount --rbind /sysroot/tmp /sysroot/root/tmp
        mount --rbind /sysroot/nix /sysroot/root/nix
        mount --rbind /sysroot/root /sysroot
      '';
    };
    fileSystems."/" = lib.mkForce {
      device = "/dev/nvme0n1";
      fsType = "bcachefs";
      options = [
        "x-initrd.mount"
        "degraded"
      ];
    };
    virtualisation.fileSystems."/" = lib.mkForce {
      device = "/dev/nvme0n1";
      fsType = "bcachefs";
      options = [
        "x-initrd.mount"
        "degraded"
      ];
    };
  };

  makeUsbNode =
    id:
    { config, pkgs, ... }:
    let
      uki = "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
      espImage = makeEspImage {
        inherit id uki;
        diskGuid =
          if id == "stick-a" then
            "11111111-1111-4111-8111-111111111111"
          else
            "22222222-2222-4222-8222-222222222222";
        partGuid =
          if id == "stick-a" then
            "11111111-1111-4111-8111-111111111112"
          else
            "22222222-2222-4222-8222-222222222223";
        systemd = config.systemd.package;
      };
    in
    {
      imports = [ (rootReset pkgs) ];
      boot.kernelParams = [ "prototype-usb=${id}" ];
      boot.loader.efi.canTouchEfiVariables = false;
      boot.loader.grub.enable = false;
      boot.loader.systemd-boot.enable = false;
      boot.uki.name = "integrated-${id}";
      boot.uki.version = null;
      environment.systemPackages = [ pkgs.bcachefs-tools ];
      system.stateVersion = "25.11";
      virtualisation.mountHostNixStore = true;
      virtualisation.useBootLoader = true;
      virtualisation.useEFIBoot = true;
      virtualisation.installBootLoader = false;
      virtualisation.efi.keepVariables = false;
      virtualisation.qemu.options = [
        "-device qemu-xhci,id=usb-controller"
        "-drive if=none,id=usb-esp,file=${espImage},format=raw,snapshot=on"
        "-device usb-storage,drive=usb-esp,bootindex=0"
      ];
    };
in
pkgs.testers.runNixOSTest {
  name = "bcachefs-integrated-usb-nvme-root";

  nodes = {
    prep =
      { pkgs, ... }:
      {
        boot.supportedFilesystems = [ "bcachefs" ];
        environment.systemPackages = [ pkgs.bcachefs-tools ];
        system.stateVersion = "25.11";
      };
    stickA = makeUsbNode "stick-a";
    stickB = makeUsbNode "stick-b";
  };

  testScript = ''
    import os
    import shutil

    base_qemu_opts = os.environ.get("QEMU_OPTS", "")

    def configure_nvme(machine, source_images=None, device_count=2):
        images = [machine.state_dir / f"nvme-{index}.img" for index in range(2)]
        for index, image in enumerate(images):
            if source_images is None:
                with open(image, "wb") as disk:
                    disk.truncate(1024 * 1024 * 1024)
            else:
                shutil.copyfile(source_images[index], image)
        qemu_opts = base_qemu_opts
        for index, image in enumerate(images[:device_count]):
            qemu_opts += (
                f" -drive file={image},format=raw,if=none,id=integrated-nvme-{index}"
                f" -device nvme,drive=integrated-nvme-{index},serial=integrated-nvme-{index}"
            )
        os.environ["QEMU_OPTS"] = qemu_opts
        return images

    prep_images = configure_nvme(prep)
    prep.start(allow_reboot=True)
    prep.wait_for_unit("multi-user.target")
    prep.succeed("test -b /dev/nvme0n1 && test -b /dev/nvme1n1")
    prep.succeed("bcachefs format --replicas=2 --fs_label=integrated-root /dev/nvme0n1 /dev/nvme1n1")
    prep.succeed("mkdir -p /mnt && mount -t bcachefs /dev/nvme0n1 /mnt")
    prep.succeed("bcachefs subvolume create /mnt/root")
    prep.succeed("bcachefs subvolume create /mnt/nix")
    prep.succeed("bcachefs subvolume snapshot --read-only /mnt/root /mnt/root-blank")
    prep.succeed("printf persistent > /mnt/nix/prototype-marker")
    prep.succeed("umount /mnt && sync")
    prep.shutdown()

    for machine, stick, device_count in [(stickA, "stick-a", 2), (stickB, "stick-b", 1)]:
        configure_nvme(machine, prep_images, device_count)
        machine.start(allow_reboot=True)
        machine.wait_for_unit("multi-user.target")
        cmdline = machine.succeed("cat /proc/cmdline")
        assert f"prototype-usb={stick}" in cmdline, cmdline
        if device_count == 1:
            machine.succeed("test -b /dev/nvme0n1 && test ! -b /dev/nvme1n1")
        machine.succeed("test \"$(findmnt -n -o FSTYPE /)\" = bcachefs")
        machine.succeed("test \"$(cat /nix/prototype-marker)\" = persistent")
        machine.succeed("bcachefs fs usage /")
        machine.succeed("printf volatile > /var/lib/integrated-root-marker")
        machine.reboot()
        machine.wait_for_unit("multi-user.target")
        machine.succeed("test ! -e /var/lib/integrated-root-marker")
        machine.succeed("test \"$(cat /nix/prototype-marker)\" = persistent")
        machine.shutdown()
  '';
}
