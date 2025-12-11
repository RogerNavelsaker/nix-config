{ lib, ... }:
{
  # Boot configuration
  # SSH keys loading is handled in load-keys.nix
  boot = {
    #kernelParams = [ "copytoram" ];
    loader.grub = {
      memtest86.enable = lib.mkForce false;
      #useOSProber = false;
    };
  };
}
