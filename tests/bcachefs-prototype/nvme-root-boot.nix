{ pkgs }:
let
  inherit (pkgs) lib;
in
pkgs.testers.runNixOSTest {
  name = "bcachefs-nvme-root-boot-prototype";

  nodes.machine = { pkgs, ... }: {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.supportedFilesystems = [ "bcachefs" ];
    environment.systemPackages = [ pkgs.bcachefs-tools ];
    system.stateVersion = "25.11";

    virtualisation = {
      mountHostNixStore = true;
      useBootLoader = true;
      useEFIBoot = true;
    };

    specialisation.bcachefs-nvme-root.configuration = {
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
  };

  testScript = ''
    import os

    nvme_images = [machine.state_dir / f"nvme-{i}.img" for i in range(2)]
    for image in nvme_images:
        with open(image, "wb") as disk:
            disk.truncate(1024 * 1024 * 1024)

    qemu_opts = os.environ.get("QEMU_OPTS", "")
    for index, image in enumerate(nvme_images):
        qemu_opts += (
            f" -drive file={image},format=raw,if=none,id=bcachefs-nvme-{index}"
            f" -device nvme,drive=bcachefs-nvme-{index},serial=prototype-nvme-{index}"
        )
    os.environ["QEMU_OPTS"] = qemu_opts

    machine.start(allow_reboot=True)
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test -b /dev/nvme0n1 && test -b /dev/nvme1n1")
    machine.succeed("bcachefs format --replicas=2 --fs_label=nvme-root /dev/nvme0n1 /dev/nvme1n1")
    machine.succeed("mkdir -p /mnt && mount -t bcachefs /dev/nvme0n1 /mnt")
    machine.succeed("bcachefs subvolume create /mnt/root")
    machine.succeed("bcachefs subvolume create /mnt/nix")
    machine.succeed("bcachefs subvolume snapshot --read-only /mnt/root /mnt/root-blank")
    machine.succeed("mkdir -p /mnt/root/var/lib")
    machine.succeed("printf volatile > /mnt/root/var/lib/bcachefs-root-marker")
    machine.succeed("printf mirrored-nvme-root > /mnt/nix/prototype-marker")
    machine.succeed("umount /mnt")

    entries = machine.succeed("bootctl list")
    specialisation_id = None
    in_specialisation = False
    for line in entries.splitlines():
        stripped = line.strip()
        if stripped.startswith("title:"):
            in_specialisation = stripped == "title: NixOS (bcachefs-nvme-root)"
        elif in_specialisation and stripped.startswith("id:"):
            specialisation_id = stripped.split(":", 1)[1].strip()
            break
    assert specialisation_id is not None, "NVMe Bcachefs root specialisation boot entry not found"
    machine.succeed(f"bootctl set-default {specialisation_id}")
    machine.reboot()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test \"$(findmnt -n -o FSTYPE /)\" = bcachefs")
    machine.succeed("test \"$(cat /nix/prototype-marker)\" = mirrored-nvme-root")
    machine.succeed("test ! -e /var/lib/bcachefs-root-marker")
    machine.succeed("printf volatile > /var/lib/bcachefs-root-marker")
    machine.reboot()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test ! -e /var/lib/bcachefs-root-marker")
    machine.succeed("test \"$(cat /nix/prototype-marker)\" = mirrored-nvme-root")
    machine.succeed("printf volatile > /var/lib/bcachefs-root-marker")
    machine.succeed("touch /nix/prototype-interrupt-reset-once")
    machine.reboot()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test \"$(findmnt -n -o FSTYPE /)\" = bcachefs")
    machine.succeed("test ! -e /nix/prototype-interrupt-reset-once")
    machine.succeed("test ! -e /var/lib/bcachefs-root-marker")
    machine.succeed("test \"$(cat /nix/prototype-marker)\" = mirrored-nvme-root")
    machine.succeed("bcachefs fs usage /")
  '';
}
