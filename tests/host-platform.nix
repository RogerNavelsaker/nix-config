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
    && cfg.networking.firewall.backend == "iptables"
    && cfg.virtualisation.libvirtd.enable
    && cfg.virtualisation.podman.enable
    && builtins.elem "libvirtd" cfg.users.users.rona.extraGroups
    && builtins.all hasPersistentDirectory persistedDirectories
    && lib.any (
      entry: entry.directory == ".local/share/containers"
    ) cfg.environment.persistence."/persist".users.rona.directories
    && builtins.elem "sops-install-secrets.service" cfg.systemd.services.k3s.requires
    && builtins.elem "avahi-daemon.service" cfg.systemd.services.k3s.after
    && cfg.services.avahi.nssmdns4
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
        builtins.elem 10250 cfg.networking.firewall.interfaces."en+".allowedTCPPorts
        && builtins.elem 8472 cfg.networking.firewall.interfaces."en+".allowedUDPPorts
        && builtins.elem 10250 cfg.networking.firewall.interfaces."eth+".allowedTCPPorts
        && builtins.elem 8472 cfg.networking.firewall.interfaces."eth+".allowedUDPPorts
        && !(builtins.elem 10250 cfg.networking.firewall.allowedTCPPorts)
        && !(builtins.elem 8472 cfg.networking.firewall.allowedUDPPorts)
    );

  transferNames = [
    "sysupdate.nanoserver.d/10-store.transfer"
    "sysupdate.nanoserver.d/20-registration.transfer"
    "sysupdate.nanoserver.d/80-uki-boot-a.transfer"
    "sysupdate.nanoserver.d/81-uki-boot-b.transfer"
  ];
  v3 = self.nixosConfigurations.nanoserver-01-update-v3-a.config;
  v4 = self.nixosConfigurations.nanoserver-01-update-v4-a.config;
  v3Transfers = map (name: v3.environment.etc.${name}.source) transferNames;
  v4Transfers = map (name: v4.environment.etc.${name}.source) transferNames;
  fluxManifests = self.nixosConfigurations.miniserver-01.config.services.k3s.manifests;
  fluxInstallManifest = fluxManifests."00-flux-install".source;
in
assert builtins.all profilePasses expectedProfiles;
assert !v3.services.k3s.enable;
assert !v3.virtualisation.libvirtd.enable;
assert !v3.virtualisation.podman.enable;
assert builtins.hasAttr "systemd/import-pubring.gpg" v4.environment.etc;
assert builtins.hasAttr "00-flux-install" fluxManifests;
assert builtins.hasAttr "10-flux-source" fluxManifests;
assert
  !(builtins.hasAttr "00-flux-install" self.nixosConfigurations.miniserver-02.config.services.k3s.manifests);
pkgs.runCommand "host-platform-check" { nativeBuildInputs = [ pkgs.gnugrep ]; } ''
  test -s ${fluxInstallManifest}
  grep -q 'kind: CustomResourceDefinition' ${fluxInstallManifest}
  for transfer in ${lib.concatMapStringsSep " " (path: toString path) v3Transfers}; do
    grep -q '^[[:space:]]*Verify=yes$' "$transfer"
  done
  for transfer in ${lib.concatMapStringsSep " " (path: toString path) v4Transfers}; do
    if grep -q '^[[:space:]]*Verify=yes$' "$transfer"; then
      echo "Nanoserver v4 must omit unsupported systemd-sysupdate Verify keys" >&2
      exit 1
    fi
  done
  touch "$out"
''
