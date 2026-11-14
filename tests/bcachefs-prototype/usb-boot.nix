{ pkgs }:
let
  makeEspImage = { id, uki, systemd }:
    pkgs.runCommand "bcachefs-usb-${id}-esp.img" {
      nativeBuildInputs = [ pkgs.gptfdisk pkgs.mtools ];
    } ''
      truncate -s 64M "$out"
      ${pkgs.gptfdisk}/bin/sgdisk --clear --new=1:2048:131038 --typecode=1:EF00 "$out"
      ${pkgs.mtools}/bin/mformat -i "$out@@1048576" -F -v USBESP ::
      ${pkgs.mtools}/bin/mmd -i "$out@@1048576" ::/EFI
      ${pkgs.mtools}/bin/mmd -i "$out@@1048576" ::/EFI/BOOT
      ${pkgs.mtools}/bin/mmd -i "$out@@1048576" ::/EFI/Linux
      ${pkgs.mtools}/bin/mcopy -i "$out@@1048576" \
        "${systemd}/lib/systemd/boot/efi/systemd-bootx64.efi" \
        ::/EFI/BOOT/BOOTX64.EFI
      ${pkgs.mtools}/bin/mcopy -i "$out@@1048576" "${uki}" ::/EFI/Linux/${id}.efi
    '';

  makeNode = id: { config, ... }:
    let
      uki = "${config.system.build.uki}/${config.system.boot.loader.ukiFile}";
      espImage = makeEspImage {
        inherit id;
        inherit uki;
        systemd = config.systemd.package;
      };
    in
    {
      boot.kernelParams = [ "prototype-usb=${id}" ];
      boot.loader.efi.canTouchEfiVariables = false;
      boot.uki.name = "prototype-${id}";
      boot.loader.grub.enable = false;
      boot.loader.systemd-boot.enable = false;
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
in
pkgs.testers.runNixOSTest {
  name = "bcachefs-independent-usb-boot";

  nodes = {
    stickA = makeNode "stick-a";
    stickB = makeNode "stick-b";
  };

  testScript = ''
    for machine, stick in [(stickA, "stick-a"), (stickB, "stick-b")]:
        machine.wait_for_unit("multi-user.target")
        cmdline = machine.succeed("cat /proc/cmdline")
        assert f"prototype-usb={stick}" in cmdline, cmdline
        loader = machine.succeed("bootctl status --no-pager")
        assert "EFI/BOOT/BOOTX64.EFI" in loader, loader
        assert f"Current Entry: {stick}.efi" in loader, loader
        assert f"/EFI/Linux/{stick}.efi" in loader, loader
        machine.succeed("test -e /sys/firmware/efi/fw_platform_size")
  '';
}
