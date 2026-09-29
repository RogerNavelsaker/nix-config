{
  config,
  pkgs,
  secrets,
  ...
}:
let
  runtimeHostname = pkgs.writeShellScript "rescue-tailscale-hostname" ''
    set -eu
    identity=""
    for path in /sys/class/dmi/id/product_uuid /etc/machine-id; do
      if [ -r "$path" ]; then
        identity=$(cat "$path")
        [ -n "$identity" ] && break
      fi
    done
    if [ -z "$identity" ]; then
      for path in /sys/class/net/*/address; do
        [ "$(basename "$(dirname "$path")")" = lo ] && continue
        identity=$(cat "$path")
        [ -n "$identity" ] && break
      done
    fi
    [ -n "$identity" ] || exit 1
    suffix=$(printf '%s' "$identity" | ${pkgs.coreutils}/bin/sha256sum | cut -c1-10)
    printf 'rescue-%s\n' "$suffix"
  '';
  authKeyPath = config.sops.secrets."ts-auth-key".path;
in
{
  # Keep daemon state in memory; rescue credentials must never persist.
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    extraDaemonFlags = [ "--state=mem:" ];
  };

  networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];

  sops.useSystemdActivation = true;
  sops.age.sshKeyPaths = [ "/run/rescue/ssh_host_ed25519_key" ];

  # Drop the temporary SOPS identity after all secrets have been materialized.
  systemd.services.sops-install-secrets.serviceConfig.ExecStartPost =
    "${pkgs.coreutils}/bin/rm -f /run/rescue/ssh_host_ed25519_key";

  sops.secrets."ts-auth-key" = {
    sopsFile = secrets + "/hosts/${config.networking.hostName}/secrets.yaml";
    key = "tailscale/auth_key";
    mode = "0400";
    restartUnits = [ ];
  };

  systemd.services.tailscale-autoconnect = {
    description = "Join restricted rescue node to Tailscale";
    after = [ "network-online.target" "sops-install-secrets.service" "tailscaled.service" ];
    wants = [ "network-online.target" "tailscaled.service" ];
    requires = [ "sops-install-secrets.service" "tailscaled.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.coreutils ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "tailscale-rescue-up" ''
        set -eu
        auth_key=${authKeyPath}
        test -s "$auth_key"
        hostname=$(${runtimeHostname})
        ${pkgs.tailscale}/bin/tailscale up \
          --authkey="file:$auth_key" \
          --hostname="$hostname" \
          --advertise-tags=tag:rescue \
          --accept-dns=false
        rm -f "$auth_key"
      '';
    };
  };
}
