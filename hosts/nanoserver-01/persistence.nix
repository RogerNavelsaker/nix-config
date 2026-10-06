{ nix-lib, ... }:
{
  # Tailscale's service state is part of this host's persistence policy.
  environment.persistence."/persist".directories =
    nix-lib.impermanence.mkPersistDirs "root" "root" "0755"
      [
        "/var/lib/tailscale"
      ];
}
