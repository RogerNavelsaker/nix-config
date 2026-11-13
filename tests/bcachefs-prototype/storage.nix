{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "bcachefs-storage-prototype";

  nodes.machine = { pkgs, ... }: {
    boot.supportedFilesystems.bcachefs = true;
    environment.systemPackages = [ pkgs.bcachefs-tools ];
    system.stateVersion = "25.11";
    virtualisation.emptyDiskImages = [ 512 512 ];
  };

  testScript = ''
    machine.succeed("modprobe bcachefs")
    machine.succeed("bcachefs format --replicas=2 --fs_label=prototype /dev/vdb /dev/vdc")
    machine.succeed("mkdir -p /mnt/pool /mnt/root /mnt/nix")
    machine.succeed("mount -t bcachefs /dev/vdb /mnt/pool")

    machine.succeed("bcachefs subvolume create /mnt/pool/root")
    machine.succeed("bcachefs subvolume create /mnt/pool/nix")
    machine.succeed("printf baseline > /mnt/pool/root/baseline")
    machine.succeed("bcachefs subvolume snapshot --read-only /mnt/pool/root /mnt/pool/root-blank")
    machine.succeed("printf persistent-nix > /mnt/pool/nix/marker")

    machine.succeed("mount --bind /mnt/pool/root /mnt/root")
    machine.succeed("mount --bind /mnt/pool/nix /mnt/nix")
    machine.succeed("grep -Fxq baseline /mnt/root/baseline")
    machine.succeed("grep -Fxq persistent-nix /mnt/nix/marker")
    machine.succeed("printf volatile-root > /mnt/root/volatile")

    machine.succeed("umount /mnt/root && umount /mnt/nix")
    machine.succeed("bcachefs subvolume delete /mnt/pool/root")
    machine.succeed("bcachefs subvolume snapshot --rw /mnt/pool/root-blank /mnt/pool/root")
    machine.succeed("mount --bind /mnt/pool/root /mnt/root")
    machine.succeed("test ! -e /mnt/root/volatile")
    machine.succeed("grep -Fxq baseline /mnt/root/baseline")
    machine.succeed("grep -Fxq persistent-nix /mnt/pool/nix/marker")

    machine.succeed("bcachefs device offline --force /dev/vdc")
    machine.succeed("printf degraded-write > /mnt/root/degraded")
    machine.succeed("bcachefs device online /dev/vdc")
    machine.succeed("grep -Fxq degraded-write /mnt/root/degraded")
    machine.succeed("bcachefs fs usage /mnt/pool")
  '';
}
