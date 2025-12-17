# hosts/iso/gpg-initrd.nix
# GPG/Yubikey smartcard support in initrd for boot-time key decryption
{ pkgs, ... }:
{
  # Enable GPG support in initrd (adds gpg, gpg-agent, scdaemon)
  boot.initrd.luks.gpgSupport = true;

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

    # Additional utilities for pass and smartcard operations
    extraUtilsCommands = ''
      # pcscd for smartcard daemon
      copy_bin_and_libs ${pkgs.pcsclite}/bin/pcscd

      # pinentry for GPG PIN prompts in console
      copy_bin_and_libs ${pkgs.pinentry-curses}/bin/pinentry-curses

      # pass for password store access
      copy_bin_and_libs ${pkgs.pass}/bin/pass

      # tree for pass internal use
      copy_bin_and_libs ${pkgs.tree}/bin/tree

      # getopt for pass argument parsing
      copy_bin_and_libs ${pkgs.util-linux}/bin/getopt

      # bash required by pass
      copy_bin_and_libs ${pkgs.bash}/bin/bash
    '';

    # Ensure pcscd has access to USB devices
    extraUtilsCommandsTest = ''
      $out/bin/pcscd --version
      $out/bin/pinentry-curses --version || true
    '';
  };

  # pcscd configuration for smartcard access
  environment.etc."reader.conf.d/.keep".text = "";
}
