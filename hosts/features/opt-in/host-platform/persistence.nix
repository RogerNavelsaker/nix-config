{ nix-lib, ... }:
{
  environment.persistence."/persist".directories =
    nix-lib.impermanence.mkPersistDirs "root" "root" "0755"
      [
        "/var/lib/containers"
        "/var/lib/kubelet"
        "/var/lib/libvirt"
        "/var/lib/rancher"
      ];

  # Keep per-user rootless Podman layers and container state across ephemeral-root boots.
  environment.persistence."/persist".users.rona.directories = [
    ".local/share/containers"
  ];
}
