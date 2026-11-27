{ pkgs, workload }:
let
  workloadRuntimeClosure = pkgs.closureInfo {
    rootPaths = [
      pkgs.nix
      pkgs.bashInteractive
      pkgs.coreutils
      workload
    ];
  };

  workloadProbe = pkgs.writeText "nanoserver-workload-probe.sh" ''
    #!/bin/sh
    set -eu

    if ${pkgs.coreutils}/bin/touch /etc/workload-nix-escape-probe 2>/dev/null; then
      ${pkgs.coreutils}/bin/rm -f /etc/workload-nix-escape-probe
      echo "workload user unexpectedly wrote to /etc" >&2
      exit 1
    fi

    printf '%s\n' workload-store-run-ok > /persist/nix-workload/run-marker
  '';

  workloadBuilderProbe = pkgs.writeText "nanoserver-workload-builder-probe.nix" ''
    let
      builderPath = builtins.storePath ${pkgs.bashInteractive};
    in
    builtins.derivation {
      name = "nanoserver-workload-bash-builder-probe";
      system = "${pkgs.stdenv.hostPlatform.system}";
      builder = builtins.toString builderPath + "/bin/bash";
      inputSrcs = [ builderPath ];
      args = [ "-c" "printf '%s\\n' workload-build-ok > $out" ];
    }
  '';

  workloadGenerationProbe =
    version:
    pkgs.writeText "nanoserver-workload-${version}.nix" ''
      let
        builderPath = builtins.storePath ${pkgs.bashInteractive};
      in
      builtins.derivation {
        name = "nanoserver-workload-${version}";
        system = "${pkgs.stdenv.hostPlatform.system}";
        builder = builtins.toString builderPath + "/bin/bash";
        inputSrcs = [ builderPath ];
        args = [
          "-c"
          "printf '%s\\n' '#!${pkgs.bashInteractive}/bin/bash' 'echo workload-${version}' > $out"
        ];
      }
    '';
in
pkgs.testers.runNixOSTest {
  name = "nanoserver-workload-appliance-runtime";

  nodes.machine = {
    environment = {
      etc = {
        "workload-nix-bootstrap".source = pkgs.nix;
        "workload-runtime-closure".source = workloadRuntimeClosure;
        "workload-probe".source = workloadProbe;
        "workload-builder-probe.nix".source = workloadBuilderProbe;
        "workload-generation-v1.nix".source = workloadGenerationProbe "v1";
        "workload-generation-v2.nix".source = workloadGenerationProbe "v2";
        "workload-example-output".text = "${workload}";
      };
      systemPackages = [
        pkgs.btrfs-progs
        pkgs.util-linux
      ];
    };

    boot.supportedFilesystems = [ "btrfs" ];
    nix.enable = false;
    system.stateVersion = "25.11";
    users.users.workload = {
      isNormalUser = true;
      createHome = true;
      group = "users";
    };

    virtualisation = {
      emptyDiskImages = [ 512 ];
      fileSystems."/" = {
        device = pkgs.lib.mkForce "tmpfs";
        fsType = pkgs.lib.mkForce "tmpfs";
        options = pkgs.lib.mkForce [ "mode=0755" ];
      };
      mountHostNixStore = false;
      useNixStoreImage = true;
      writableStore = false;
    };
  };

  testScript = ''
    machine.succeed("test \"$(findmnt -n -o FSTYPE /)\" = tmpfs")
    machine.succeed("findmnt -n -o OPTIONS /nix/store | tr ',' '\\n' | grep -Fxq ro")
    machine.succeed("! command -v nix")
    machine.succeed("! systemctl is-active --quiet nix-daemon.service")
    machine.succeed("test ! -S /nix/var/nix/daemon-socket/socket")

    system_toplevel = machine.succeed("readlink -f /run/current-system").strip()
    system_store_digest = machine.succeed(
        "find /nix/store -mindepth 1 -maxdepth 1 -type d | sort | sha256sum"
    ).strip()
    machine.succeed("! touch /nix/store/workload-base-store-write-probe")
    machine.succeed("touch /root/workload-volatile-marker")

    machine.succeed("mkfs.btrfs -f /dev/vdc")
    machine.succeed("mkdir -p /mnt/persist-root && mount /dev/vdc /mnt/persist-root")
    machine.succeed("btrfs subvolume create /mnt/persist-root/@persist")
    machine.succeed("umount /mnt/persist-root && mkdir -p /persist && mount -o subvol=@persist /dev/vdc /persist")
    machine.succeed("test \"$(findmnt -n -o FSTYPE /persist)\" = btrfs")
    machine.succeed("install -d -m 0755 -o workload -g users /persist/nix-workload")
    machine.succeed("install -d -m 0700 -o workload -g users /persist/nix-workload/root")
    machine.succeed("install -m 0644 -o workload -g users /etc/workload-probe /persist/nix-workload/probe.sh")
    machine.succeed("install -m 0644 -o workload -g users /etc/workload-builder-probe.nix /persist/nix-workload/builder-probe.nix")

    workload_root = "/persist/nix-workload/root"
    machine.succeed("install -d -m 0755 -o workload -g users " + workload_root + "/nix")
    machine.succeed("install -d -m 0755 -o workload -g users " + workload_root + "/nix/store")
    machine.succeed(
        "while IFS= read -r path; do cp -a \"$path\" "
        + workload_root
        + "/nix/store/; done < /etc/workload-runtime-closure/store-paths"
    )
    machine.succeed(
        "runuser -u workload -- /etc/workload-nix-bootstrap/bin/nix-store --store "
        + workload_root
        + " --load-db < /etc/workload-runtime-closure/registration"
    )
    workload_nix = workload_root + "${pkgs.nix}/bin/nix"
    machine.succeed("test -x " + workload_nix)
    built_path = machine.succeed(
        "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' "
        + workload_nix
        + " --store "
        + workload_root
        + " --option sandbox true --offline build --file /persist/nix-workload/builder-probe.nix --no-link --print-out-paths"
    ).strip().splitlines()[-1]
    assert built_path.startswith("/nix/store/"), built_path
    machine.succeed("test -f " + workload_root + built_path)
    machine.succeed(
        "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' "
        + workload_nix
        + " --store "
        + workload_root
        + " store cat "
        + built_path
        + " | grep -Fxq workload-build-ok"
    )

    active_root = "/persist/nix-workload/active"
    machine.succeed("install -d -m 0700 -o workload -g users " + active_root)
    workload_uid = machine.succeed("id -u workload").strip()
    workload_gid = machine.succeed("id -g workload").strip()
    workload_groups = ",".join(machine.succeed("id -G workload").split())

    def build_generation(version):
        path = machine.succeed(
            "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' "
            + workload_nix
            + " --store "
            + workload_root
            + " --option sandbox true --offline build --file /etc/workload-generation-"
            + version
            + ".nix --no-link --print-out-paths"
        ).strip().splitlines()[-1]
        assert path.startswith("/nix/store/"), path
        return path

    generation_v1 = build_generation("v1")
    generation_v2 = build_generation("v2")
    for generation_path, expected_version in [
        (generation_v1, "workload-v1"),
        (generation_v2, "workload-v2"),
    ]:
        machine.succeed("test -f " + workload_root + generation_path)
        machine.succeed(
            "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' "
            + workload_nix
            + " --store "
            + workload_root
            + " store cat "
            + generation_path
            + " | grep -Fq "
            + expected_version
        )

    machine.succeed(
        "/etc/workload-nix-bootstrap/bin/nix-store --store "
        + workload_root
        + " --generate-binary-cache-key workload-test "
        "/root/workload-test-secret.key /root/workload-test-public.key"
    )
    workload_public_key = machine.succeed("cat /root/workload-test-public.key").strip()
    machine.succeed(
        "env NIX_CONFIG='experimental-features = nix-command' "
        + workload_nix
        + " --store "
        + workload_root
        + " copy --to file:///persist/nix-workload/unsigned-cache "
        + generation_v1
        + " "
        + generation_v2
    )
    machine.succeed(
        "/etc/workload-nix-bootstrap/bin/nix-store --store "
        + workload_root
        + " --query --requisites "
        + generation_v1
        + " "
        + generation_v2
        + " > /persist/nix-workload/signing-inputs"
    )
    machine.succeed(
        "env NIX_CONFIG='experimental-features = nix-command' "
        + workload_nix
        + " --store "
        + workload_root
        + " store sign --key-file /root/workload-test-secret.key --stdin "
        + "< /persist/nix-workload/signing-inputs"
    )
    machine.succeed(
        "env NIX_CONFIG='experimental-features = nix-command' "
        + workload_nix
        + " --store "
        + workload_root
        + " --option trusted-public-keys '"
        + workload_public_key
        + "' store verify --recursive --sigs-needed 1 "
        + generation_v1
    )
    machine.succeed(
        "env NIX_CONFIG='experimental-features = nix-command' "
        + workload_nix
        + " --store "
        + workload_root
        + " --option secret-key-files /root/workload-test-secret.key copy --to "
        + "file:///persist/nix-workload/signed-cache "
        + generation_v1
        + " "
        + generation_v2
    )
    machine.succeed(
        "chmod -R a+rX /persist/nix-workload/signed-cache "
        "/persist/nix-workload/unsigned-cache"
    )

    workload_nix_env = (
        "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' "
        + workload_nix
    )
    workload_trust = (
        " --option trusted-public-keys '"
        + workload_public_key
        + "' --option require-sigs true "
    )
    machine.succeed(
        "! "
        + workload_nix_env
        + workload_trust
        + "copy --from file:///persist/nix-workload/unsigned-cache --to "
        + active_root
        + " "
        + generation_v1
    )
    machine.succeed("test ! -e " + active_root + generation_v1)

    def import_signed_generation(generation_path):
        machine.succeed(
            workload_nix_env
            + workload_trust
            + "copy --from file:///persist/nix-workload/signed-cache --to "
            + active_root
            + " "
            + generation_path
        )
        machine.succeed(
            workload_nix_env
            + " --store "
            + active_root
            + " --option trusted-public-keys '"
            + workload_public_key
            + "' store verify --recursive --sigs-needed 1 "
            + generation_path
        )

    def activate_generation(generation_path, expected_version):
        machine.succeed(
            "runuser -u workload -- /bin/sh -c \"printf '%s' "
            + generation_path
            + " > /persist/nix-workload/current-generation\""
        )
        active_generation = machine.succeed(
            "cat /persist/nix-workload/current-generation"
        ).strip()
        assert active_generation == generation_path
        machine.succeed(
            "chroot --userspec="
            + workload_uid
            + ":"
            + workload_gid
            + " --groups="
            + workload_groups
            + " "
            + active_root
            + " ${pkgs.bashInteractive}/bin/bash "
            + active_generation
            + " | grep -Fxq "
            + expected_version
        )

    import_signed_generation(generation_v1)
    activate_generation(generation_v1, "workload-v1")
    import_signed_generation(generation_v2)
    activate_generation(generation_v2, "workload-v2")
    activate_generation(generation_v1, "workload-v1")

    workload_output = machine.succeed("cat /etc/workload-example-output").strip()
    assert workload_output.startswith("/nix/store/"), workload_output
    workload_executable = workload_output + "/bin/hello"
    workload_physical_executable = workload_root + workload_executable
    machine.succeed("test -x " + workload_physical_executable)

    def run_workload_package():
        machine.succeed(
            "chroot --userspec="
            + workload_uid
            + ":"
            + workload_gid
            + " --groups="
            + workload_groups
            + " "
            + workload_root
            + " "
            + workload_executable
            + " | grep -Fxq 'Hello, world!'"
        )

    run_workload_package()
    machine.succeed("chown workload:users " + workload_root + "/nix/store")
    machine.succeed("test -w " + workload_root + "/nix/store")

    stored_path = machine.succeed(
        "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' "
        + workload_nix
        + " --store "
        + workload_root
        + " store add --name workload-probe --mode flat /persist/nix-workload/probe.sh"
    ).strip().splitlines()[-1]
    assert stored_path.startswith("/nix/store/"), stored_path
    physical_path = workload_root + stored_path
    machine.succeed("test -f " + physical_path)

    def run_workload():
        machine.succeed(
            "unshare --mount --propagation private /bin/sh -c 'exec "
            + "${pkgs.util-linux}/bin/setpriv --reuid=workload --regid=users --init-groups /bin/sh "
            + physical_path
            + "'"
        )

    run_workload()
    machine.succeed("test -f /persist/nix-workload/run-marker")
    machine.succeed("! test -e /etc/workload-nix-escape-probe")
    machine.succeed(
        "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' "
        + workload_nix
        + " --store "
        + workload_root
        + " store cat "
        + stored_path
        + " | grep -Fxq '#!/bin/sh'"
    )
    assert machine.succeed("readlink -f /run/current-system").strip() == system_toplevel
    assert machine.succeed(
        "find /nix/store -mindepth 1 -maxdepth 1 -type d | sort | sha256sum"
    ).strip() == system_store_digest

    machine.shutdown()
    machine.start()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("test \"$(findmnt -n -o FSTYPE /)\" = tmpfs")
    machine.succeed("test ! -e /root/workload-volatile-marker")
    machine.succeed("findmnt -n -o OPTIONS /nix/store | tr ',' '\\n' | grep -Fxq ro")
    machine.succeed("mkdir -p /persist && mount -o subvol=@persist /dev/vdc /persist")
    machine.succeed("test -f /persist/nix-workload/root/nix/var/nix/db/db.sqlite")
    machine.succeed("test -f " + active_root + "/nix/var/nix/db/db.sqlite")
    machine.succeed("test ! -e /root/workload-test-secret.key")
    assert machine.succeed("cat /persist/nix-workload/current-generation").strip() == generation_v1
    machine.succeed("test -f " + active_root + generation_v1)
    machine.succeed(
        "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' "
        + workload_nix
        + " --store "
        + active_root
        + " --option trusted-public-keys '"
        + workload_public_key
        + "' store verify --recursive --sigs-needed 1 "
        + generation_v1
    )
    activate_generation(generation_v1, "workload-v1")
    machine.succeed("test -f /persist/nix-workload/run-marker")
    machine.succeed("test -x " + workload_nix)
    machine.succeed("test -f " + workload_root + built_path)
    machine.succeed(
        "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' "
        + workload_nix
        + " --store "
        + workload_root
        + " store cat "
        + built_path
        + " | grep -Fxq workload-build-ok"
    )
    machine.succeed("test -x " + workload_physical_executable)
    run_workload_package()
    machine.succeed("! systemctl is-active --quiet nix-daemon.service")
    machine.succeed("test ! -S /nix/var/nix/daemon-socket/socket")
    run_workload()
    machine.succeed("test -f /persist/nix-workload/run-marker")
    machine.succeed("! test -e /etc/workload-nix-escape-probe")
    machine.succeed(
        "runuser -u workload -- env NIX_CONFIG='experimental-features = nix-command' "
        + workload_nix
        + " --store "
        + workload_root
        + " store cat "
        + stored_path
        + " | grep -Fxq '#!/bin/sh'"
    )
    assert machine.succeed("readlink -f /run/current-system").strip() == system_toplevel
    assert machine.succeed(
        "find /nix/store -mindepth 1 -maxdepth 1 -type d | sort | sha256sum"
    ).strip() == system_store_digest
  '';
}
