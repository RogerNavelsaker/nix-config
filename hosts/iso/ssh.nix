{ lib, ... }:
{
  # SSH configuration
  # Host keys will be loaded from external sources or generated on first boot
  # Key loading logic is handled in load-keys.nix
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AuthorizedKeysFile = "/home/rona/.ssh/authorized_keys";
    };
  };

  systemd.services.sshd = {
    wantedBy = lib.mkForce [ "multi-user.target" ];
    requires = [ "sops-install-secrets.service" ];
    after = [ "sops-install-secrets.service" ];
  };
}
