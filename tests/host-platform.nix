{
  pkgs,
  lib,
  self,
}:
let
  expectedProfiles = [
    {
      name = "miniserver-01";
      role = "server";
      clusterInit = true;
      serverAddr = "";
    }
    {
      name = "miniserver-01-slot-b";
      role = "server";
      clusterInit = true;
      serverAddr = "";
    }
    {
      name = "miniserver-02";
      role = "server";
      clusterInit = false;
      serverAddr = "https://miniserver-01.local:6443";
    }
    {
      name = "miniserver-02-slot-b";
      role = "server";
      clusterInit = false;
      serverAddr = "https://miniserver-01.local:6443";
    }
    {
      name = "miniserver-03";
      role = "server";
      clusterInit = false;
      serverAddr = "https://miniserver-01.local:6443";
    }
    {
      name = "miniserver-03-slot-b";
      role = "server";
      clusterInit = false;
      serverAddr = "https://miniserver-01.local:6443";
    }
    {
      name = "nanoserver-01-update-v4-a";
      role = "agent";
      clusterInit = false;
      serverAddr = "https://miniserver-01.local:6443";
    }
    {
      name = "nanoserver-01-update-v4-b";
      role = "agent";
      clusterInit = false;
      serverAddr = "https://miniserver-01.local:6443";
    }
  ];

  persistedDirectories = [
    "/var/lib/containers"
    "/var/lib/kubelet"
    "/var/lib/libvirt"
    "/var/lib/rancher"
  ];

  profilePasses =
    profile:
    let
      cfg = self.nixosConfigurations.${profile.name}.config;
      persistence = cfg.environment.persistence."/persist".directories;
      hasPersistentDirectory = directory: lib.any (entry: entry.directory == directory) persistence;
      k3s = cfg.services.k3s;
    in
    k3s.enable
    && k3s.role == profile.role
    && k3s.clusterInit == profile.clusterInit
    && k3s.serverAddr == profile.serverAddr
    && k3s.token == ""
    && k3s.tokenFile != null
    && k3s.nodeName == cfg.networking.hostName
    && !(builtins.elem "--docker" k3s.extraFlags)
    && (
      profile.role != "server"
      || builtins.all (flag: builtins.elem flag k3s.extraFlags) [
        "--cluster-cidr=10.42.0.0/16"
        "--flannel-backend=vxlan"
        "--service-cidr=10.43.0.0/16"
        "--tls-san=miniserver-01.local"
      ]
    )
    && cfg.virtualisation.libvirtd.enable
    && cfg.virtualisation.podman.enable
    && builtins.elem "libvirtd" cfg.users.users.rona.extraGroups
    && builtins.all hasPersistentDirectory persistedDirectories
    && lib.any (
      entry: entry.directory == ".local/share/containers"
    ) cfg.environment.persistence."/persist".users.rona.directories
    && builtins.elem "sops-install-secrets.service" cfg.systemd.services.k3s.requires
    && (
      if profile.role == "server" then
        builtins.all (port: builtins.elem port cfg.networking.firewall.interfaces.eno1.allowedTCPPorts) [
          6443
          10250
          2379
          2380
        ]
        && builtins.elem 8472 cfg.networking.firewall.interfaces.eno1.allowedUDPPorts
      else
        builtins.elem 10250 cfg.networking.firewall.allowedTCPPorts
        && builtins.elem 8472 cfg.networking.firewall.allowedUDPPorts
    );

  v3 = self.nixosConfigurations.nanoserver-01-update-v3-a.config;
  fluxManifests = self.nixosConfigurations.miniserver-01.config.services.k3s.manifests;
  fluxInstallManifest = fluxManifests."00-flux-install".source;
in
assert builtins.all profilePasses expectedProfiles;
assert !v3.services.k3s.enable;
assert !v3.virtualisation.libvirtd.enable;
assert !v3.virtualisation.podman.enable;
assert builtins.hasAttr "00-flux-install" fluxManifests;
assert builtins.hasAttr "10-flux-source" fluxManifests;
assert
  !(builtins.hasAttr "00-flux-install" self.nixosConfigurations.miniserver-02.config.services.k3s.manifests);
pkgs.runCommand "host-platform-check" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  test -s ${fluxInstallManifest}
  grep -q 'kind: CustomResourceDefinition' ${fluxInstallManifest}
  touch "$out"
''
