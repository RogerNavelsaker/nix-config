{ pkgs }:
let
  workloadImage =
    version:
    pkgs.dockerTools.buildImage {
      name = "nanoserver-workload-probe";
      tag = version;
      copyToRoot = pkgs.buildEnv {
        name = "nanoserver-workload-probe-root";
        paths = [ pkgs.busybox ];
        pathsToLink = [ "/bin" ];
      };
      config.Cmd = [
        "/bin/busybox"
        "sh"
        "-c"
        "test ! -e /run/workload-host-marker; printf '${version}\\n' > /state/current; exec /bin/busybox sleep 600"
      ];
    };

  workloadRuntimeClosure = pkgs.closureInfo {
    rootPaths = [
      pkgs.nix
      (workloadImage "v1")
      (workloadImage "v2")
    ];
  };

  quadlet =
    version:
    pkgs.writeText "nanoserver-workload-probe.container" ''
      [Unit]
      Description=Rootless workload Nix prototype fixture

      [Container]
      Image=localhost/nanoserver-workload-probe:${version}
      ContainerName=nanoserver-workload-probe
      Network=none
      Volume=/persist/nix-workload/state:/state:rw

      [Service]
      Restart=no

      [Install]
      WantedBy=default.target
    '';
in
pkgs.testers.runNixOSTest {
  name = "nanoserver-workload-rootless-podman-quadlet";

  nodes.machine = {
    environment = {
      etc = {
        "workload-runtime-closure".source = workloadRuntimeClosure;
        "nanoserver-workload-v1.oci.tar".source = workloadImage "v1";
        "nanoserver-workload-v2.oci.tar".source = workloadImage "v2";
        "nanoserver-workload-probe.container".source = quadlet "v1";
      };
      systemPackages = [
        pkgs.nix
        pkgs.util-linux
        pkgs.e2fsprogs
        pkgs.podman
        pkgs.fuse-overlayfs
      ];
    };

    nix.enable = false;
    # Only the unprivileged API is in scope; keep the package's rootful socket off.
    virtualisation.podman = {
      enable = true;
      dockerCompat = false;
      dockerSocket.enable = false;
    };
    systemd.sockets.podman.enable = false;
    systemd.services.podman.enable = false;

    users.users.workload = {
      isNormalUser = true;
      createHome = true;
      group = "users";
      subUidRanges = [
        {
          startUid = 100000;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = 100000;
          count = 65536;
        }
      ];
    };

    system.stateVersion = "25.11";
    virtualisation.emptyDiskImages = [ 1024 ];
  };

  testScript = ''
    machine.succeed("mkdir -p /persist && mkfs.ext4 -F /dev/vdb && mount -t ext4 /dev/vdb /persist")
    machine.succeed("test \"$(findmnt -n -o FSTYPE /persist)\" = ext4")
    machine.succeed("install -d -m 0700 -o workload -g users /persist/nix-workload/root")
    machine.succeed("install -d -m 0755 -o workload -g users /persist/nix-workload/root/nix")
    machine.succeed("install -d -m 0755 -o workload -g users /persist/nix-workload/root/nix/store")
    machine.succeed("install -d -m 0700 -o workload -g users /persist/nix-workload/active")
    machine.succeed("install -d -m 0750 -o workload -g users /persist/nix-workload/state")
    machine.succeed("printf 'host-only-marker\\n' > /run/workload-host-marker")

    system_toplevel = machine.succeed("readlink -f /run/current-system").strip()
    system_store_digest = machine.succeed(
        "find /nix/store -mindepth 1 -maxdepth 1 -type d | sort | sha256sum"
    ).strip()
    machine.succeed("! systemctl is-active --quiet nix-daemon.service")
    machine.succeed("test ! -S /nix/var/nix/daemon-socket/socket")

    workload_root = "/persist/nix-workload/root"
    active_root = "/persist/nix-workload/active"
    workload_nix = "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' nix"
    source_nix = workload_nix + " --store " + workload_root
    machine.succeed(
        "while IFS= read -r path; do cp -a \"$path\" "
        + workload_root
        + "/nix/store/; done < /etc/workload-runtime-closure/store-paths"
    )
    machine.succeed(
        "runuser -u workload -- nix-store --store "
        + workload_root
        + " --load-db < /etc/workload-runtime-closure/registration"
    )
    image_path_v1 = machine.succeed("readlink -f /etc/nanoserver-workload-v1.oci.tar").strip()
    image_path_v2 = machine.succeed("readlink -f /etc/nanoserver-workload-v2.oci.tar").strip()
    assert image_path_v1.startswith("/nix/store/"), image_path_v1
    assert image_path_v2.startswith("/nix/store/"), image_path_v2
    for image_path in [ image_path_v1, image_path_v2 ]:
        machine.succeed("test -f " + workload_root + image_path)

    machine.succeed(
        "nix-store --store "
        + workload_root
        + " --generate-binary-cache-key workload-test "
        "/root/workload-test-secret.key /root/workload-test-public.key"
    )
    workload_public_key = machine.succeed("cat /root/workload-test-public.key").strip()
    machine.succeed("install -d -m 0755 /persist/nix-workload/unsigned-cache /persist/nix-workload/signed-cache")
    machine.succeed(
        "env NIX_CONFIG='experimental-features = nix-command' nix --store "
        + workload_root
        + " copy --to file:///persist/nix-workload/unsigned-cache "
        + image_path_v1
        + " "
        + image_path_v2
    )
    machine.succeed(
        "nix-store --store "
        + workload_root
        + " --query --requisites "
        + image_path_v1
        + " "
        + image_path_v2
        + " > /persist/nix-workload/signing-inputs"
    )
    machine.succeed(
        "env NIX_CONFIG='experimental-features = nix-command' nix --store "
        + workload_root
        + " store sign --key-file /root/workload-test-secret.key --stdin "
        + "< /persist/nix-workload/signing-inputs"
    )
    machine.succeed(
        "env NIX_CONFIG='experimental-features = nix-command' nix --store "
        + workload_root
        + " --option trusted-public-keys '"
        + workload_public_key
        + "' store verify --recursive --sigs-needed 1 "
        + image_path_v1
        + " "
        + image_path_v2
    )
    machine.succeed(
        "env NIX_CONFIG='experimental-features = nix-command' nix --store "
        + workload_root
        + " --option secret-key-files /root/workload-test-secret.key copy --to "
        + "file:///persist/nix-workload/signed-cache "
        + image_path_v1
        + " "
        + image_path_v2
    )
    machine.succeed(
        "chmod -R a+rX /persist/nix-workload/unsigned-cache "
        "/persist/nix-workload/signed-cache"
    )

    workload_trust = (
        " --option trusted-public-keys '"
        + workload_public_key
        + "' --option require-sigs true "
    )
    machine.succeed(
        "! "
        + workload_nix
        + workload_trust
        + "copy --from file:///persist/nix-workload/unsigned-cache --to "
        + active_root
        + " "
        + image_path_v1
    )
    machine.succeed("test ! -e " + active_root + image_path_v1)
    machine.succeed(
        workload_nix
        + workload_trust
        + "copy --from file:///persist/nix-workload/signed-cache --to "
        + active_root
        + " "
        + image_path_v1
        + " "
        + image_path_v2
    )
    for image_path in [ image_path_v1, image_path_v2 ]:
        machine.succeed(
            workload_nix
            + " --store "
            + active_root
            + " --option trusted-public-keys '"
            + workload_public_key
            + "' store verify --recursive --sigs-needed 1 "
            + image_path
        )
        machine.succeed("test -f " + active_root + image_path)

    physical_image_v1 = active_root + image_path_v1
    physical_image_v2 = active_root + image_path_v2
    workload_uid = machine.succeed("id -u workload").strip()
    machine.succeed("systemctl start network-online.target")
    machine.succeed("loginctl enable-linger workload")
    machine.wait_for_unit("user@" + workload_uid + ".service")
    user_systemctl = (
        "runuser -u workload -- env XDG_RUNTIME_DIR=/run/user/" + workload_uid
        + " DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/" + workload_uid
        + "/bus systemctl --user "
    )
    user_podman = "runuser -u workload -- podman "
    machine.succeed(user_podman + "info --format '{{.Host.Security.Rootless}}' | grep -Fxq true")
    machine.succeed(user_podman + "load --input " + physical_image_v1)
    machine.succeed(user_podman + "load --input " + physical_image_v2)

    quadlet_path = "/home/workload/.config/containers/systemd/nanoserver-workload-probe.container"
    machine.succeed(
        "install -d -m 0755 -o workload -g users /home/workload/.config/containers/systemd "
        "&& install -o workload -g users /etc/nanoserver-workload-probe.container "
        + quadlet_path
    )
    machine.succeed(user_systemctl + "daemon-reload")
    machine.succeed(user_systemctl + "start nanoserver-workload-probe.service")
    machine.succeed("grep -Fxq v1 /persist/nix-workload/state/current")
    machine.succeed(
        user_podman
        + "inspect --format '{{.Config.Image}}' nanoserver-workload-probe "
        + "| grep -Fxq localhost/nanoserver-workload-probe:v1"
    )

    machine.succeed("sed -i 's/:v1$/:v2/' " + quadlet_path)
    machine.succeed(user_systemctl + "daemon-reload")
    machine.succeed(user_systemctl + "restart nanoserver-workload-probe.service")
    machine.succeed("grep -Fxq v2 /persist/nix-workload/state/current")
    machine.succeed(
        user_podman
        + "inspect --format '{{.Config.Image}}' nanoserver-workload-probe "
        + "| grep -Fxq localhost/nanoserver-workload-probe:v2"
    )

    machine.succeed("sed -i 's/:v2$/:v1/' " + quadlet_path)
    machine.succeed(user_systemctl + "daemon-reload")
    machine.succeed(user_systemctl + "restart nanoserver-workload-probe.service")
    machine.succeed("grep -Fxq v1 /persist/nix-workload/state/current")
    machine.succeed(
        user_podman
        + "inspect --format '{{.Config.Image}}' nanoserver-workload-probe "
        + "| grep -Fxq localhost/nanoserver-workload-probe:v1"
    )

    machine.succeed(user_podman + "ps --filter name=nanoserver-workload-probe --format '{{.Names}}' | grep -Fxq nanoserver-workload-probe")
    machine.succeed("test ! -S /run/podman/podman.sock")
    machine.succeed("test ! -S /run/docker.sock")
    assert machine.succeed("find /nix/store -mindepth 1 -maxdepth 1 -type d | sort | sha256sum").strip() == system_store_digest
    assert machine.succeed("readlink -f /run/current-system").strip() == system_toplevel

    machine.succeed(user_systemctl + "stop nanoserver-workload-probe.service")
  '';
}
