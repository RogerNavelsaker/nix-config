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

  # The shared token is installed by sops-nix at boot before K3s consumes it.
  systemd.services.k3s = {
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
  };

  # Miniservers use the hardware-verified wired interface eno1. Keep the API,
  # embedded-etcd, kubelet, and Flannel ports off their WLAN interfaces.
  networking.firewall.interfaces = lib.mkIf isControlPlane {
    eno1 = {
      allowedTCPPorts = [
        10250
      ]
      ++ lib.optionals isControlPlane [
        6443
        2379
        2380
      ];
      allowedUDPPorts = [ 8472 ];
    };
  };

  # Nanoserver's hardware uses different/variable wired interface names. It is
  # an agent only, so expose no API-server or etcd port; open only kubelet and
  # Flannel's required host ports while allowing outbound API connections.
  networking.firewall.allowedTCPPorts = lib.mkIf isNanoserver [ 10250 ];
  networking.firewall.allowedUDPPorts = lib.mkIf isNanoserver [ 8472 ];
}
