{ nix-lib, ... }:
{
  environment.persistence."/persist".directories =
    nix-lib.impermanence.mkPersistDirs "root" "root" "0755"
      [
        "/var/lib/tailscale"
      ];
}
