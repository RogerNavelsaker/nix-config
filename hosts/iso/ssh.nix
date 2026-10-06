{ config, lib, ... }:
let
  lanMode = builtins.elem config.rescueIso.networkMode [
    "lan"
    "rescue-lan"
  ];
in
{
  services.openssh = {
    enable = lib.mkForce lanMode;
    openFirewall = lib.mkForce lanMode;
    settings = lib.mkIf lanMode {
      AllowUsers = [ "rona" ];
      PermitRootLogin = "no";
      PermitEmptyPasswords = false;
      PasswordAuthentication = true;
      KbdInteractiveAuthentication = false;
      PubkeyAuthentication = false;
    };
  };

  systemd.services.sshd = lib.mkIf lanMode {
    requires = [ "sops-install-secrets.service" ];
    after = [
      "network.target"
      "sops-install-secrets.service"
    ];
  };
}
