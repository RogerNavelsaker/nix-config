{ pkgs }:
let
  makeEspImage = {
    id,
    diskGuid,
    partGuid,
    uki,
    systemd,
    ukiName ? id,
  }:
    pkgs.runCommand "bcachefs-usb-${id}-esp.img" {
      nativeBuildInputs = [ pkgs.gptfdisk pkgs.mtools ];
    } ''
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
      ${pkgs.mtools}/bin/mcopy -i "$out@@1048576" "${uki}" ::/EFI/Linux/${ukiName}.efi
    '';

  makeNode = { id, diskGuid, partGuid }: { config, ... }:
    let
      uki = "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
      espImage = makeEspImage {
        inherit id diskGuid partGuid uki;
        systemd = config.systemd.package;
      };
    in
    {
      boot.kernelParams = [ "prototype-usb=${id}" ];
      boot.loader.efi.canTouchEfiVariables = false;
      boot.loader.grub.enable = false;
      boot.loader.systemd-boot.enable = false;
      boot.uki.name = "prototype-${id}";
      boot.uki.version = null;
      system.stateVersion = "25.11";
      virtualisation.useBootLoader = true;
      virtualisation.useEFIBoot = true;
      virtualisation.installBootLoader = false;
      virtualisation.efi.keepVariables = false;
      virtualisation.qemu.options = [
        "-device qemu-xhci,id=usb-controller"
        "-drive if=none,id=usb-esp,file=${espImage},format=raw,readonly=on"
        "-device usb-storage,drive=usb-esp,bootindex=0"
      ];
    };

  makeSyncNode = { config, ... }:
    let
      ukiV1 = "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
      ukiSettingsV2 = pkgs.lib.recursiveUpdate config.boot.uki.settings {
        UKI.Cmdline = pkgs.lib.replaceStrings
          [ "prototype-generation=v1" ]
          [ "prototype-generation=v2" ]
          config.boot.uki.settings.UKI.Cmdline;
      };
      ukiConfigV2 = (pkgs.formats.ini { }).generate "prototype-sync-v2.ukify.conf" ukiSettingsV2;
      ukiV2 = pkgs.runCommand "prototype-sync-v2.efi" { } ''
        ${pkgs.buildPackages.systemdUkify}/lib/systemd/ukify build \
          --config=${ukiConfigV2} \
          --output="$out"
      '';
      espA = makeEspImage {
        id = "sync-a";
        diskGuid = "33333333-3333-4333-8333-333333333333";
        partGuid = "33333333-3333-4333-8333-333333333334";
        ukiName = "generation-1";
        uki = ukiV1;
        systemd = config.systemd.package;
      };
      espB = makeEspImage {
        id = "sync-b";
        diskGuid = "44444444-4444-4444-8444-444444444444";
        partGuid = "44444444-4444-4444-8444-444444444445";
        ukiName = "generation-1";
        uki = ukiV1;
        systemd = config.systemd.package;
      };
    in
    {
      boot.kernelParams = [ "prototype-usb=sync" "prototype-generation=v1" ];
      boot.loader.efi.canTouchEfiVariables = false;
      boot.loader.grub.enable = false;
      boot.loader.systemd-boot.enable = false;
      boot.uki.name = "prototype-sync";
      boot.uki.version = null;
      system.build.prototypeSyncUkiV2 = ukiV2;
      environment.systemPackages = [ pkgs.util-linux ];
      virtualisation.mountHostNixStore = true;
      system.stateVersion = "25.11";
      virtualisation.useBootLoader = true;
      virtualisation.useEFIBoot = true;
      virtualisation.installBootLoader = false;
      virtualisation.efi.keepVariables = false;
      virtualisation.qemu.options = [
        "-device qemu-xhci,id=usb-controller"
        "-drive if=none,id=usb-esp-a,file=${espA},format=raw,snapshot=on"
        "-device usb-storage,drive=usb-esp-a,bootindex=0"
        "-drive if=none,id=usb-esp-b,file=${espB},format=raw,snapshot=on"
        "-device usb-storage,drive=usb-esp-b,bootindex=2"
      ];
    };
in
pkgs.testers.runNixOSTest {
  name = "bcachefs-independent-usb-boot";

  nodes = {
    stickA = makeNode {
      id = "stick-a";
      diskGuid = "11111111-1111-4111-8111-111111111111";
      partGuid = "11111111-1111-4111-8111-111111111112";
    };
    stickB = makeNode {
      id = "stick-b";
      diskGuid = "22222222-2222-4222-8222-222222222222";
      partGuid = "22222222-2222-4222-8222-222222222223";
    };
    sync = makeSyncNode;
  };

  testScript = { nodes, ... }: ''
    for machine, stick in [(stickA, "stick-a"), (stickB, "stick-b")]:
        machine.wait_for_unit("multi-user.target")
        cmdline = machine.succeed("cat /proc/cmdline")
        assert f"prototype-usb={stick}" in cmdline, cmdline
        loader = machine.succeed("bootctl status --no-pager")
        assert "EFI/BOOT/BOOTX64.EFI" in loader, loader
        assert f"Current Entry: {stick}.efi" in loader, loader
        assert f"/EFI/Linux/{stick}.efi" in loader, loader
        machine.succeed("test -e /sys/firmware/efi/fw_platform_size")

    sync.wait_for_unit("multi-user.target")
    cmdline = sync.succeed("cat /proc/cmdline")
    assert "prototype-generation=v1" in cmdline, cmdline
    loader = sync.succeed("bootctl status --no-pager")
    assert "by-partuuid/33333333-3333-4333-8333-333333333334" in loader, loader

    sync.succeed("mkdir -p /mnt/esp-a /mnt/esp-b")
    sync.succeed("mount -t vfat /dev/disk/by-partuuid/33333333-3333-4333-8333-333333333334 /mnt/esp-a")
    sync.succeed("mount -t vfat /dev/disk/by-partuuid/44444444-4444-4444-8444-444444444445 /mnt/esp-b")
    sync.succeed("cmp /mnt/esp-a/EFI/BOOT/BOOTX64.EFI /mnt/esp-b/EFI/BOOT/BOOTX64.EFI")
    sync.succeed("cmp /mnt/esp-a/EFI/Linux/generation-1.efi /mnt/esp-b/EFI/Linux/generation-1.efi")

    # Commit each ESP update separately so the untouched peer stays bootable.
    sync.succeed("cp ${nodes.sync.system.build.prototypeSyncUkiV2} /mnt/esp-a/EFI/Linux/generation-2.efi.tmp")
    sync.succeed("sync && mv /mnt/esp-a/EFI/Linux/generation-2.efi.tmp /mnt/esp-a/EFI/Linux/generation-2.efi && sync")
    sync.succeed("test -s /mnt/esp-b/EFI/BOOT/BOOTX64.EFI && test -s /mnt/esp-b/EFI/Linux/generation-1.efi")
    sync.succeed("test ! -e /mnt/esp-b/EFI/Linux/generation-2.efi")

    sync.succeed("cp ${nodes.sync.system.build.prototypeSyncUkiV2} /mnt/esp-b/EFI/Linux/generation-2.efi.tmp")
    sync.succeed("sync && mv /mnt/esp-b/EFI/Linux/generation-2.efi.tmp /mnt/esp-b/EFI/Linux/generation-2.efi && sync")
    sync.succeed("cmp /mnt/esp-a/EFI/Linux/generation-2.efi /mnt/esp-b/EFI/Linux/generation-2.efi")
    sync.succeed("diff -r /mnt/esp-a/EFI /mnt/esp-b/EFI")
    sync.succeed("umount /mnt/esp-a /mnt/esp-b")
  '';
}
