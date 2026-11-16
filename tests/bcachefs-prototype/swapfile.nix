{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "bcachefs-swapfile-rejection";

  nodes.machine = { pkgs, ... }: {
    boot.supportedFilesystems.bcachefs = true;
    environment.systemPackages = [ pkgs.bcachefs-tools ];
    system.stateVersion = "25.11";
    virtualisation.emptyDiskImages = [ 512 512 ];
  };

  testScript = ''
    machine.succeed("modprobe bcachefs")
    machine.succeed("bcachefs format --replicas=2 --fs_label=swap-prototype /dev/vdb /dev/vdc")
    machine.succeed("mkdir -p /mnt/pool && mount -t bcachefs /dev/vdb /mnt/pool")

    machine.succeed("dd if=/dev/zero of=/mnt/pool/swapfile bs=1M count=64 conv=fsync status=none && chmod 0600 /mnt/pool/swapfile")
    machine.succeed("mkswap /mnt/pool/swapfile")
    machine.succeed("! swapon /mnt/pool/swapfile")
    machine.succeed("test -z \"$(swapon --show --noheadings)\"")
    machine.succeed("umount /mnt/pool")
  '';
}
