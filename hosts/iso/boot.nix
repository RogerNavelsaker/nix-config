{ lib, ... }:
{
  boot.loader.grub.memtest86.enable = lib.mkForce false;
  boot.loader.timeout = 10;
  # Keep the rescue environment usable after its boot medium is detached.
  boot.kernelParams = [ "copytoram" ];
  isoImage.configurationName = "WAN";

  # These specialisations become explicit ISO GRUB entries. The WAN base
  # system stays the safe default; each entry builds one network/SSH policy.
  specialisation = {
    lan.configuration = {
      rescueIso.networkMode = "lan";
      isoImage.configurationName = lib.mkForce "LAN";
    };

    rescue-lan.configuration = {
      rescueIso.networkMode = "rescue-lan";
      isoImage.configurationName = lib.mkForce "Rescue LAN";
    };
  };
}
