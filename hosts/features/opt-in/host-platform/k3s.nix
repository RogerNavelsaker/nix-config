{
  config,
  inputs,
  lib,
  ...
}:
let
  hostName = config.networking.hostName;
  isNanoserver = hostName == "nanoserver-01";
  isControlPlane = builtins.elem hostName [
    "miniserver-01"
    "miniserver-02"
    "miniserver-03"
  ];
  isBootstrap = hostName == "miniserver-01";
  apiEndpoint = "https://miniserver-01.local:6443";
  clusterTokenFile = config.sops.secrets."k3s-cluster-token".path;
in
{
  assertions = [
    {
      assertion = isNanoserver || isControlPlane;
      message = "host-platform is only defined for nanoserver-01 and miniserver-01/02/03";
    }
    {
      assertion = config.networking.firewall.backend == "iptables";
      message = "host-platform uses iptables interface-prefix matching for Nanoserver's wired K3s ports";
    }
  ];

  sops.secrets."k3s-cluster-token" = {
    sopsFile = inputs.nix-secrets-cluster + "/clusters/nanoserver-miniservers/secrets.yaml";
    key = "k3s/token";
    mode = "0400";
  };

  services.k3s = {
    enable = true;
    role = if isNanoserver then "agent" else "server";
    clusterInit = isBootstrap;
    serverAddr = if isBootstrap then "" else apiEndpoint;
    tokenFile = clusterTokenFile;
    nodeName = hostName;
    extraFlags = lib.optionals isControlPlane [
      "--cluster-cidr=10.42.0.0/16"
      "--flannel-backend=vxlan"
      "--service-cidr=10.43.0.0/16"
      "--tls-san=miniserver-01.local"
    ];
  };

  # Make the Avahi .local endpoint resolvable by libc clients and start K3s
  # after both the resolver and its host token are available.
  services.avahi.nssmdns4 = true;
  systemd.services.k3s = {
    after = [
      "sops-install-secrets.service"
      "avahi-daemon.service"
    ];
    requires = [ "sops-install-secrets.service" ];
    wants = [ "avahi-daemon.service" ];
  };

  # Miniservers use the hardware-verified wired interface eno1. Keep the API,
  # embedded-etcd, kubelet, and Flannel ports off their WLAN interfaces.
  networking.firewall.interfaces = lib.mkMerge [
    (lib.mkIf isControlPlane {
      eno1 = {
        allowedTCPPorts = [
          6443
          10250
          2379
          2380
        ];
        allowedUDPPorts = [ 8472 ];
      };
    })
    # Nanoserver's wired names vary, but its networkd rules match en* and eth*.
    # iptables' trailing + matches those prefixes without opening ports on WLAN.
    (lib.mkIf isNanoserver {
      "en+" = {
        allowedTCPPorts = [ 10250 ];
        allowedUDPPorts = [ 8472 ];
      };
      "eth+" = {
        allowedTCPPorts = [ 10250 ];
        allowedUDPPorts = [ 8472 ];
      };
    })
  ];
}
