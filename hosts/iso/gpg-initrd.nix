# hosts/iso/gpg-initrd.nix
# GPG/Yubikey smartcard support in initrd for boot-time key decryption
{ pkgs, ... }:
{
  boot.initrd = {
    # Kernel modules for USB smartcard/Yubikey
    kernelModules = [
      "usbhid"
      "usb_storage"
    ];
    availableKernelModules = [
      "usbhid"
      "usb_storage"
    ];

    # Stage the complete GPG smartcard stack explicitly. The NixOS LUKS GPG
    # option only adds these binaries when an initrd LUKS device is configured.
    extraUtilsCommands = ''
      copy_bin_and_libs ${pkgs.gnupg}/bin/gpg
      copy_bin_and_libs ${pkgs.gnupg}/bin/gpg-agent
      copy_bin_and_libs ${pkgs.gnupg}/bin/gpgconf
      copy_bin_and_libs ${pkgs.gnupg}/bin/gpg-connect-agent
      copy_bin_and_libs ${pkgs.gnupg}/libexec/scdaemon
      copy_bin_and_libs ${pkgs.pcsclite}/bin/pcscd
      # Use the real client library; the Nix wrapper dlopens its store path.
      copy_bin_and_libs ${pkgs.pcsclite.lib}/lib/libpcsclite_real.so.1
      copy_bin_and_libs ${pkgs.ccid}/pcsc/drivers/ifd-ccid.bundle/Contents/Linux/libccid.so
      mkdir -p $out/var/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Linux
      cp ${pkgs.ccid}/pcsc/drivers/ifd-ccid.bundle/Contents/Info.plist \
        $out/var/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Info.plist
      ln -s ../../../../../../../bin/libccid.so \
        $out/var/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Linux/libccid.so
      copy_bin_and_libs ${pkgs.pinentry-tty}/bin/pinentry-tty
      cp ${pkgs.pass}/bin/.pass-wrapped $out/bin/pass
      sed -i "1s|^#!.*$|#!$out/bin/bash|" $out/bin/pass
      copy_bin_and_libs ${pkgs.tree}/bin/tree
      copy_bin_and_libs ${pkgs.util-linux}/bin/getopt
      copy_bin_and_libs ${pkgs.bash}/bin/bash
      copy_bin_and_libs ${pkgs.busybox}/bin/busybox
    '';

    extraUtilsCommandsTest = ''
      $out/bin/gpg --version
      $out/bin/gpg-agent --version
      $out/bin/gpgconf --version
      $out/bin/gpg-connect-agent --version
      $out/bin/scdaemon --version
      $out/bin/pcscd --version
      test -s $out/bin/libpcsclite_real.so.1
      $out/bin/pinentry-tty --version
      test -x $out/bin/bash
      $out/bin/timeout 1s true
      $out/bin/date +%s >/dev/null
      test -s $out/var/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Info.plist
      test -L $out/var/lib/pcsc/drivers/ifd-ccid.bundle/Contents/Linux/libccid.so
      $out/bin/pass --version
    '';
  };

  # pcscd configuration for smartcard access
  environment.etc."reader.conf.d/.keep".text = "";
}
