{
  diskoLib,
  diskoModule,
  lib,
  pkgs,
  self,
}:
let
  finalSystem = self.nixosConfigurations.miniserver-01.extendModules {
    modules = [
      (
        { config, pkgs, ... }:
        {
          boot.kernelParams = [ "console=ttyS0,115200n8" ];
          systemd.services.miniserver-final-qemu-boot-proof = {
            description = "Disposable QEMU proof that the final Miniserver appliance booted";
            wantedBy = [ "multi-user.target" ];
            after = [
              "local-fs.target"
              "sops-install-secrets.service"
            ];
            requires = [ "sops-install-secrets.service" ];
            serviceConfig.RequiresMountsFor = [ "/persist" ];
            serviceConfig.Type = "oneshot";
            serviceConfig.StandardOutput = "journal+console";
            script = ''
              set -eux
              test "$(${pkgs.coreutils}/bin/cat ${config.sops.secrets."rona-password".path})" = test-hash
              test "$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE /)" = tmpfs
              test "$(${pkgs.util-linux}/bin/findmnt -n -T /nix/store -o FSTYPE | ${pkgs.coreutils}/bin/head -n1)" = btrfs
              ${pkgs.util-linux}/bin/findmnt -n -T /nix/store -o FSROOT | ${pkgs.coreutils}/bin/head -n1 | grep -Fx "/${config.appliance.storeName}_${config.appliance.rootVersion}"
              ${pkgs.util-linux}/bin/findmnt -n -T /nix/store -o OPTIONS | ${pkgs.coreutils}/bin/head -n1 | grep -Eq '(^|,)ro(,|$)'
              echo 'final appliance booted' > /persist/miniserver-qemu-first-boot-proof
              ${pkgs.coreutils}/bin/sync
              echo MINISERVER_FINAL_APPLIANCE_BOOT_OK > /dev/ttyS0
              ${pkgs.systemd}/bin/systemctl poweroff --no-block
            '';
          };
        }
      )
    ];
  };
  final = finalSystem.config;
  bootstrapSystem = self.nixosConfigurations.miniserver-01-bootstrap.extendModules {
    modules = [
      ({ lib, ... }: {
        appliance.bootstrap = {
          finalToplevelName = lib.mkForce (builtins.baseNameOf (toString final.system.build.toplevel));
          finalStoreTarball = lib.mkForce "${final.system.build.applianceStoreTarball}/${final.appliance.storeName}_${final.appliance.rootVersion}.tar.xz";
          finalStoreRegistration = lib.mkForce (toString final.system.build.applianceStoreRegistration);
          finalSlotAuki = lib.mkForce "${final.system.build.uki}/${final.system.boot.loader.ukiFile}";
          finalSlotAukiFile = lib.mkForce final.system.boot.loader.ukiFile;
        };
      })
    ];
  };
  bootstrap = bootstrapSystem.config;
  inherit (bootstrap.appliance) btrfs;
  inherit (bootstrap.appliance.update) rootPoolPath;
  bootstrapToplevel = toString bootstrap.system.build.toplevel;
  bootstrapStoreSubvolume = "${bootstrap.appliance.storeName}_${bootstrap.appliance.rootVersion}";
  finalStoreSubvolume = "${final.appliance.storeName}_${final.appliance.rootVersion}";
  finalStorePath = "/mnt${rootPoolPath}/${finalStoreSubvolume}";
  bootstrapStorePath = "/mnt${rootPoolPath}/${bootstrapStoreSubvolume}";
  finalPasswordStorePath = "${finalStorePath}/${
    lib.removePrefix "/nix/store/" (toString final.sops.secrets."rona-password".sopsFile)
  }";
  finalTailscaleStorePath = "${finalStorePath}/${
    lib.removePrefix "/nix/store/" (toString final.sops.secrets."ts-auth-key".sopsFile)
  }";
  dataPartUuidA = bootstrap.appliance.btrfs.dataPartUuidA;
  dataPartUuidB = bootstrap.appliance.btrfs.dataPartUuidB;
  espPartUuidA = bootstrap.appliance.devices.espPartUuidA;
  usbRootPartUuidA = bootstrap.appliance.btrfs.rootPartUuidA;
  usbRootPartUuidB = bootstrap.appliance.btrfs.rootPartUuidB;
  finalRegistrationPath = "/mnt/persist/${final.appliance.name}/store-registrations/${finalStoreSubvolume}.registration";
  finalToplevelName = builtins.baseNameOf (toString final.system.build.toplevel);
  finalSlotBUki = self.nixosConfigurations.miniserver-01-slot-b.config;
  cleanupScript = pkgs.writeShellScriptBin "miniserver-bootstrap-cleanup-install-test" (
    final.systemd.services."${final.appliance.name}-bootstrap-store-cleanup".script
  );
  passwordSopsFile = toString bootstrap.sops.secrets."rona-password".sopsFile;
  tailscaleSopsFile = toString bootstrap.sops.secrets."ts-auth-key".sopsFile;
  targetStoreFile = path: "/mnt${path}";
  diskConfig = diskoLib.testLib.prepareDiskoConfig {
    disko.devices = bootstrap.disko.devices;
  } (builtins.tail diskoLib.testLib.devices);
in
pkgs.testers.runNixOSTest {
  name = "miniserver-bootstrap-install-activation";
  nodes.machine = { config, ... }: {
    imports = [
      diskoModule
      diskConfig
    ];
    disko.enableConfig = false;
    boot.loader.systemd-boot.enable = true;
    services.openssh.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    boot.supportedFilesystems = [
      "btrfs"
      "vfat"
    ];
    environment.systemPackages = [
      pkgs.btrfs-progs
      cleanupScript
      pkgs.coreutils
      pkgs.openssh
      pkgs.sops
      pkgs.ssh-to-age
      pkgs.qemu_kvm
      pkgs.util-linux
      pkgs.nixos-install-tools
      pkgs.nix
    ];
    system.stateVersion = "25.11";
    system.extraDependencies = [
      config.system.build.format
      config.system.build.mount
      bootstrap.system.build.toplevel
    ];
    virtualisation.memorySize = 4096;
    virtualisation.cores = 4;
    virtualisation.emptyDiskImages = lib.mkForce [
      65536
      65536
      65536
      65536
    ];
    virtualisation.useBootLoader = true;
    virtualisation.useEFIBoot = true;
  };
  testScript =
    { nodes, ... }:
    ''
      machine.succeed("mkdir -p /mnt && mount -t tmpfs -o size=128M tmpfs /mnt")
      machine.succeed("${lib.getExe nodes.machine.system.build.format}")
      machine.succeed("${lib.getExe nodes.machine.system.build.mount}")

      # Reproduce nixos-anywhere 1.13.0's SSH remote-store transfer into /mnt.
      machine.succeed('mkdir -p /root/.ssh && chmod 0700 /root/.ssh && ssh-keygen -q -t ed25519 -N "" -f /run/nix-copy-key && cat /run/nix-copy-key.pub >> /root/.ssh/authorized_keys && chmod 0600 /root/.ssh/authorized_keys')
      copy_bootstrap_closure = 'NIX_SSHOPTS="-i /run/nix-copy-key -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null" nix --extra-experimental-features nix-command copy --to "ssh://root@localhost?remote-store=local%3Froot=%2Fmnt" ${bootstrapToplevel}'
      machine.succeed(copy_bootstrap_closure)
      machine.succeed('test "$(findmnt -n -T /mnt/nix/store -o TARGET)" = /mnt/nix/store')
      machine.succeed('test "$(findmnt -n -T /mnt/nix/store -o FSTYPE)" = btrfs')
      machine.succeed('test "$(findmnt -n -T /mnt/nix/store -o FSROOT)" = "/${bootstrapStoreSubvolume}"')
      machine.succeed('test "$(findmnt -n -T /mnt/nix/var/nix/db -o TARGET)" != /mnt/nix/store')

      # Model Disko replacing /nix/store while /nix/var/nix/db survives outside
      # the store subvolume. If Nix trusts stale validity records, nix copy will
      # skip the missing payloads; clearing that DB must make the copy complete.
      machine.succeed("""
        closure=$(nix-store -qR ${bootstrapToplevel})
        printf '%s\\n' "$closure" | while IFS= read -r path; do rm -rf "/mnt$path"; done
        test -s /mnt/nix/var/nix/db/db.sqlite
        missing=$(printf '%s\\n' "$closure" | while IFS= read -r path; do test -e "/mnt$path" || printf '%s\\n' "$path"; done)
        total=$(printf '%s\\n' "$closure" | wc -l)
        missing_count=$(printf '%s\\n' "$missing" | wc -l)
        test "$missing_count" -eq "$total"
      """)
      machine.succeed(copy_bootstrap_closure)
      machine.succeed("""
        closure=$(nix-store -qR ${bootstrapToplevel})
        total=$(printf '%s\\n' "$closure" | wc -l)
        missing=$(printf '%s\\n' "$closure" | while IFS= read -r path; do test -e "/mnt$path" || printf '%s\\n' "$path"; done)
        missing_count=$(printf '%s\\n' "$missing" | wc -l)
        echo "Stale target DB copy result: $((total - missing_count))/$total closure paths present"
        test "$missing_count" -eq "$total"
      """)
      closure_count = len(machine.succeed("nix-store -qR ${bootstrapToplevel}").splitlines())
      machine.log(f"Stale Nix database reproduced: nix copy left all {closure_count} closure paths absent.")
      machine.succeed("rm -rf /mnt/nix/var/nix/db")
      machine.succeed(copy_bootstrap_closure)
      machine.succeed("""
        closure=$(nix-store -qR ${bootstrapToplevel})
        total=$(printf '%s\\n' "$closure" | wc -l)
        missing=$(printf '%s\\n' "$closure" | while IFS= read -r path; do test -e "/mnt$path" || printf '%s\\n' "$path"; done)
        if [ -n "$missing" ]; then missing_count=$(printf '%s\\n' "$missing" | wc -l); else missing_count=0; fi
        echo "Fresh target DB copy result: $((total - missing_count))/$total closure paths present"
        test "$missing_count" -eq 0
        test -e "/mnt${bootstrapToplevel}/activate"
        test -x "/mnt${bootstrapToplevel}/sw/bin/bash"
      """)
      machine.log(f"Fresh Nix database restored all {closure_count} bootstrap closure paths.")

      # Model nixos-anywhere's root-shaped --extra-files transfer into /mnt.
      machine.succeed("mkdir -p /run/extra-files/persist/etc/ssh")
      machine.succeed("chmod 0700 /run/extra-files /run/extra-files/persist /run/extra-files/persist/etc /run/extra-files/persist/etc/ssh")
      machine.succeed('ssh-keygen -q -t ed25519 -N "" -f /run/extra-files/persist/etc/ssh/ssh_host_ed25519_key')
      machine.succeed("chmod 0600 /run/extra-files/persist/etc/ssh/ssh_host_ed25519_key")
      machine.succeed("mkdir -p /mnt/persist/etc/ssh && cp -a /run/extra-files/persist/etc/ssh/. /mnt/persist/etc/ssh/")
      machine.succeed('test "$(stat -c %a /mnt/persist/etc/ssh/ssh_host_ed25519_key)" = 600')
      machine.succeed("test ! -e /mnt/etc/ssh/ssh_host_ed25519_key")

      # Install the actual bootstrap toplevel as nixos-install does, deferring
      # its bootloader/activation pass so encrypted disposable test fixtures can
      # replace the real secret files after closure copying but before activation.
      machine.succeed("nixos-install --no-root-passwd --no-channel-copy --no-bootloader --system ${bootstrapToplevel}")
      machine.succeed('test "$(readlink -f /mnt/nix/var/nix/profiles/system)" = "${bootstrapToplevel}"')
      machine.succeed("test -f ${targetStoreFile passwordSopsFile}")
      machine.succeed("test -f ${targetStoreFile tailscaleSopsFile}")

      # Replace only the copied Nix-store SOPS inputs with disposable encrypted
      # fixtures whose age recipient is the staged /persist host key.
      machine.succeed('ssh-to-age -private-key -i /mnt/persist/etc/ssh/ssh_host_ed25519_key > /run/bootstrap-test.agekey')
      machine.succeed('recipient=$(ssh-to-age -i /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub); printf "password: test-hash\\n" > /run/password.yaml; sops --encrypt --age "$recipient" --encrypted-regex "^password$" /run/password.yaml > /run/password.sops.yaml')
      machine.succeed('recipient=$(ssh-to-age -i /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub); printf "tailscale:\\n  auth_key: disposable-test-key\\n" > /run/tailscale.yaml; sops --encrypt --age "$recipient" --encrypted-regex "^auth_key$" /run/tailscale.yaml > /run/tailscale.sops.yaml')
      machine.succeed("mount --bind /run/password.sops.yaml ${targetStoreFile passwordSopsFile}")
      machine.succeed("mount --bind /run/tailscale.sops.yaml ${targetStoreFile tailscaleSopsFile}")

      # This is the nixos-anywhere 1.13.0 install action's bootloader pass:
      # nixos-enter followed by switch-to-configuration boot with the installer flag.
      machine.succeed('NIXOS_INSTALL_BOOTLOADER=1 nixos-enter --root /mnt --command "set -e; hash -r; mount --rbind --mkdir / /mnt; mount --make-rslave /mnt; /run/current-system/bin/switch-to-configuration boot; umount -R /mnt"')

      # Install activation successfully runs the SOPS setup against the staged key;
      # its /run output belongs to the install chroot and is not persistent here.
      machine.succeed('ssh-keygen -lf /run/extra-files/persist/etc/ssh/ssh_host_ed25519_key.pub | cut -d " " -f 2 > /run/staged-key.fingerprint')
      machine.succeed('ssh-keygen -lf /mnt/persist/etc/ssh/ssh_host_ed25519_key.pub | cut -d " " -f 2 > /run/installed-key.fingerprint')
      machine.succeed("cmp /run/staged-key.fingerprint /run/installed-key.fingerprint")

      machine.succeed("btrfs subvolume show ${bootstrapStorePath}")
      machine.succeed("btrfs subvolume show ${finalStorePath}")
      machine.succeed("btrfs property set -ts ${finalStorePath} ro false && chmod u+w \"$(dirname ${finalPasswordStorePath})\" \"$(dirname ${finalTailscaleStorePath})\" && cp --remove-destination /run/password.sops.yaml ${finalPasswordStorePath} && cp --remove-destination /run/tailscale.sops.yaml ${finalTailscaleStorePath} && chmod 0444 ${finalPasswordStorePath} ${finalTailscaleStorePath} && chmod u-w \"$(dirname ${finalPasswordStorePath})\" \"$(dirname ${finalTailscaleStorePath})\" && btrfs property set -ts ${finalStorePath} ro true")
      machine.succeed('test "$(btrfs property get -ts ${finalStorePath} ro)" = ro=true')
      machine.succeed("test -e ${finalStorePath}/${finalToplevelName}")
      machine.succeed("cmp ${final.system.build.applianceStoreRegistration} ${finalRegistrationPath}")
      machine.succeed("cmp ${final.system.build.uki}/${final.system.boot.loader.ukiFile} /mnt/boot/EFI/Linux/${final.system.boot.loader.ukiFile}")
      machine.succeed("cmp ${finalSlotBUki.system.build.uki}/${finalSlotBUki.system.boot.loader.ukiFile} /mnt/boot-b/EFI/Linux/${finalSlotBUki.system.boot.loader.ukiFile}")
      machine.succeed("grep -Fx 'default ${final.system.boot.loader.ukiFile}' /mnt/boot/loader/loader.conf")
      machine.succeed("grep -Fx 'default ${finalSlotBUki.system.boot.loader.ukiFile}' /mnt/boot-b/loader/loader.conf")

      machine.succeed("mkdir -p ${rootPoolPath} && mount --bind /mnt${rootPoolPath} ${rootPoolPath}")
      machine.succeed("${lib.getExe cleanupScript}")
      machine.succeed("test ! -e ${bootstrapStorePath}")
      machine.succeed("umount ${rootPoolPath}")
      machine.succeed("btrfs subvolume show ${finalStorePath}")
      machine.succeed("umount -Rv /mnt")
      machine.succeed("cp ${nodes.machine.config.virtualisation.efi.variables} /run/ovmf-vars.fd")
      machine.succeed("""
        set -eu
        disk_for_partuuid() {
          lsblk -no PKNAME "$(readlink -f "/dev/disk/by-partuuid/$1")" | tr -d ' '
        }
        usb_a=$(disk_for_partuuid ${espPartUuidA})
        usb_b=$(disk_for_partuuid ${bootstrap.appliance.devices.espPartUuidB})
        data_a=$(disk_for_partuuid ${dataPartUuidA})
        data_b=$(disk_for_partuuid ${dataPartUuidB})
        qemu-system-x86_64 -machine q35,accel=tcg -cpu max -smp 2 -m 2048 \\
          -usb -device qemu-xhci,id=xhci \\
          -drive if=pflash,format=raw,unit=0,readonly=on,file=${nodes.machine.config.virtualisation.efi.firmware} \\
          -drive if=pflash,format=raw,unit=1,file=/run/ovmf-vars.fd \\
          -drive if=none,id=usbA,file=/dev/$usb_a,format=raw -device usb-storage,drive=usbA,bus=xhci.0,bootindex=1 \\
          -drive if=none,id=usbB,file=/dev/$usb_b,format=raw -device usb-storage,drive=usbB,bus=xhci.0,bootindex=2 \\
          -drive if=virtio,file=/dev/$data_a,format=raw \\
          -drive if=virtio,file=/dev/$data_b,format=raw \\
          -display none -serial file:/run/miniserver-final-boot.log -monitor none -no-reboot &
        qemu_pid=$!
        attempt=0
        while [ "$attempt" -lt 300 ]; do
          if ! kill -0 "$qemu_pid" 2>/dev/null; then
            wait "$qemu_pid" || true
            if grep -q MINISERVER_FINAL_APPLIANCE_BOOT_OK /run/miniserver-final-boot.log; then
              exit 0
            fi
            cat /run/miniserver-final-boot.log
            exit 1
          fi
          sleep 1
          attempt=$((attempt + 1))
        done
        cat /run/miniserver-final-boot.log
        kill "$qemu_pid" || true
        wait "$qemu_pid" || true
        exit 1
      """)
      machine.succeed("mkdir -p /mnt/persist && mount -t btrfs -o degraded,subvol=@persist /dev/disk/by-partuuid/${dataPartUuidA} /mnt/persist")
      machine.succeed('proof=/mnt/persist/miniserver-qemu-first-boot-proof; if [ -e "$proof" ]; then ls -l "$proof"; od -An -tx1c "$proof"; else echo "missing persistent proof marker"; fi; test "$(cat "$proof")" = "final appliance booted"')
      machine.succeed("umount /mnt/persist")
    '';
}
