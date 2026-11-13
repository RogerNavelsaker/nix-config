{ pkgs }:
let
  inherit (pkgs) lib;
in
pkgs.testers.runNixOSTest {
  name = "bcachefs-root-boot-prototype";

  nodes.machine = { pkgs, ... }: {
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.supportedFilesystems = [ "bcachefs" ];
    environment.systemPackages = [ pkgs.bcachefs-tools pkgs.util-linux ];
    system.stateVersion = "25.11";

    virtualisation = {
      emptyDiskImages = lib.mkForce [ 512 512 ];
      mountHostNixStore = true;
      useBootLoader = true;
      useEFIBoot = true;
    };

    specialisation.bcachefs-root.configuration = {
      boot.initrd.supportedFilesystems.bcachefs = true;

      boot.initrd.systemd.services.bcachefs-root-reset = {
        description = "Recreate the disposable Bcachefs root before switch-root";
        after = [ "sysroot.mount" "sysroot-nix-store.mount" ];
        before = [ "initrd-nixos-activation.service" "initrd-switch-root.target" ];
        requires = [ "sysroot.mount" ];
        requiredBy = [ "initrd-nixos-activation.service" ];
        unitConfig.DefaultDependencies = false;
        serviceConfig.Type = "oneshot";
        path = [ pkgs.bcachefs-tools pkgs.coreutils pkgs.util-linux ];
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
        device = "/dev/vdb";
        fsType = "bcachefs";
        options = [ "x-initrd.mount" ];
      };
      virtualisation.fileSystems."/" = lib.mkForce {
        device = "/dev/vdb";
        fsType = "bcachefs";
        options = [ "x-initrd.mount" ];
      };
    };
  };

  testScript = ''
    machine.succeed("bcachefs format --replicas=2 --fs_label=prototype /dev/vdb /dev/vdc")
    machine.succeed("mkdir -p /mnt")
    machine.succeed("mount -t bcachefs /dev/vdb /mnt")
    machine.succeed("bcachefs subvolume create /mnt/root")
    machine.succeed("bcachefs subvolume create /mnt/nix")
    machine.succeed("bcachefs subvolume snapshot --read-only /mnt/root /mnt/root-blank")
    machine.succeed("printf persistent > /mnt/nix/prototype-marker")
    machine.succeed("umount /mnt")

    entries = machine.succeed("bootctl list")
    specialisation_id = None
    in_specialisation = False
    for line in entries.splitlines():
      stripped = line.strip()
      if stripped.startswith("title:"):
        in_specialisation = stripped == "title: NixOS (bcachefs-root)"
      elif in_specialisation and stripped.startswith("id:"):
        specialisation_id = stripped.split(":", 1)[1].strip()
        break
    assert specialisation_id is not None, "Bcachefs specialisation boot entry not found"
    machine.succeed(f"bootctl set-default {specialisation_id}")
    machine.crash()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test \"$(findmnt -n -o FSTYPE /)\" = bcachefs")
    machine.succeed("test \"$(cat /nix/prototype-marker)\" = persistent")
    machine.succeed("mkdir -p /var/lib && printf volatile > /var/lib/bcachefs-root-marker")
    machine.succeed("touch /nix/prototype-interrupt-reset-once")

    machine.crash()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test \"$(findmnt -n -o FSTYPE /)\" = bcachefs")
    machine.succeed("test ! -e /nix/prototype-interrupt-reset-once")
    machine.succeed("test ! -e /var/lib/bcachefs-root-marker")
    machine.succeed("test \"$(cat /nix/prototype-marker)\" = persistent")
  '';
}
