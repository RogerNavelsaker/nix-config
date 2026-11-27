{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "nanoserver-workload-nix-chroot-store";

  nodes.machine = {
    environment.systemPackages = [
      pkgs.nix
      pkgs.util-linux
      pkgs.e2fsprogs
    ];

    # The test VM supplies the Nix CLI as a bootstrap tool only. Its workload
    # store is independently rooted on a separate persistent disk and does not
    # use the VM's NixOS store or daemon.
    nix.enable = false;

    users.users.workload = {
      isNormalUser = true;
      createHome = true;
      group = "users";
    };

    system.stateVersion = "25.11";
    virtualisation.emptyDiskImages = [ 256 ];
  };

  testScript = ''
    machine.succeed("mkdir -p /persist && mkfs.ext4 -F /dev/vdb && mount -t ext4 /dev/vdb /persist")
    machine.succeed("test \"$(findmnt -n -o FSTYPE /persist)\" = ext4")
    machine.succeed("install -d -m 0700 -o workload -g users /persist/nix-workload/root")
    machine.succeed("printf 'workload-store-survives-reboot\\n' > /tmp/workload-probe")
    machine.succeed("chown workload:users /tmp/workload-probe")

    system_toplevel = machine.succeed("readlink -f /run/current-system").strip()
    system_store_digest = machine.succeed("find /nix/store -mindepth 1 -maxdepth 1 -type d | sort | sha256sum").strip()
    machine.succeed("! systemctl is-active --quiet nix-daemon.service")
    machine.succeed("test ! -S /nix/var/nix/daemon-socket/socket")

    stored_path = machine.succeed(
        "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' "
        "nix --store /persist/nix-workload/root store add --name workload-probe "
        "--mode flat /tmp/workload-probe"
    ).strip().splitlines()[-1]
    assert stored_path.startswith("/nix/store/"), stored_path
    store_basename = stored_path.rsplit("/", 1)[-1]
    machine.succeed("test -f /persist/nix-workload/root/nix/store/" + store_basename)
    machine.succeed("test ! -e /nix/store/" + store_basename)
    machine.succeed(
        "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' "
        "nix --store /persist/nix-workload/root store cat " + stored_path
        + " | grep -Fxq workload-store-survives-reboot"
    )
    assert machine.succeed("find /nix/store -mindepth 1 -maxdepth 1 -type d | sort | sha256sum").strip() == system_store_digest
    assert machine.succeed("readlink -f /run/current-system").strip() == system_toplevel

    machine.shutdown()
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /persist && mount -t ext4 /dev/vdb /persist")
    machine.succeed("test \"$(findmnt -n -o FSTYPE /persist)\" = ext4")
    machine.succeed("test -f /persist/nix-workload/root/nix/store/" + store_basename)
    machine.succeed(
        "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' "
        "nix --store /persist/nix-workload/root store cat " + stored_path
        + " | grep -Fxq workload-store-survives-reboot"
    )
    machine.succeed("! systemctl is-active --quiet nix-daemon.service")
    machine.succeed("test ! -S /nix/var/nix/daemon-socket/socket")
    assert machine.succeed("find /nix/store -mindepth 1 -maxdepth 1 -type d | sort | sha256sum").strip() == system_store_digest
    assert machine.succeed("readlink -f /run/current-system").strip() == system_toplevel
  '';
}
