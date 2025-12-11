{
  config,
  pkgs,
  secrets,
  ...
}:
{
  # Enable Tailscale service
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    extraDaemonFlags = [ "--state=mem:" ];
  };

  # Open Tailscale port
  networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];

  # Define SOPS secret for Tailscale auth key
  sops.secrets."ts-auth-key" = {
    sopsFile = secrets + "/hosts/${config.networking.hostName}/secrets.yaml";
    key = "tailscale/auth_key";
  };

  sops.templates."ts-auth-key" = {
    content = ''
      ${config.sops.placeholder."ts-auth-key"}
    '';
    path = "/etc/ts-auth-key";
    mode = "0600";
    restartUnits = [ "tailscaled.service" ];
  };

  environment.etc."tailscale-connect.sh" = {
    text = ''
      #!/bin/sh
      status="$(${pkgs.tailscale}/bin/tailscale status -json | ${pkgs.jq}/bin/jq -r .BackendState)"
      if [ "$status" != "Running" ]; then
        ${pkgs.tailscale}/bin/tailscale up --authkey file:/etc/ts-auth-key
      fi
    '';
    mode = "0755";
  };

  systemd.services.tailscale-autoconnect = {
    description = "Automatic connection to Tailscale";
    after = [ "tailscaled.service" ];
    wants = [ "tailscaled.service" ];
    requires = [ "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "/etc/tailscale-connect.sh";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/tailscale 0700 root root -"
  ];

  environment.persistence = {
    "/persist".directories = [
      {
        directory = "/var/lib/tailscale";
      }
    ];
  };
}
