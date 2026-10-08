{ nix-lib, ... }:
{
  environment.persistence."/persist".directories =
    nix-lib.impermanence.mkPersistDirs "root" "root" "0755"
      [
        "/var/lib/containers"
        "/var/lib/libvirt"
      ];

  # Keep per-user rootless Podman layers and container state across ephemeral-root boots.
  environment.persistence."/persist".users.rona.directories = [
    ".local/share/containers"
  ];
}
