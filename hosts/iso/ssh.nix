{ lib, ... }:
{
  # SSH configuration
  # Host keys will be loaded from external sources or generated on first boot
  # Key loading logic is handled in load-keys.nix
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "yes";
    # Allow default key generation for sops-nix compatibility
    # Keys from Ventoy/QEMU will overwrite these if found
  };

  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
}
