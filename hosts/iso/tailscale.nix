{
  config,
  lib,
  pkgs,
  secrets,
  ...
}:
let
  wanMode = config.rescueIso.networkMode == "wan";
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
  rescueTailscaleUp = pkgs.writeShellScriptBin "rescue-tailscale-up" ''
    set -eu
    if [ "$EUID" -ne 0 ]; then
      echo "Run with sudo after YubiKey/SOPS unlock." >&2
      exit 1
    fi

    auth_key=${authKeyPath}
    test -s "$auth_key" || {
      echo "Tailscale auth key is unavailable; unlock SOPS secrets first." >&2
      exit 1
    }

    hostname=$(${runtimeHostname})
    ${pkgs.tailscale}/bin/tailscale up \
      --authkey="file:$auth_key" \
      --hostname="$hostname" \
      --advertise-tags=tag:rescue \
      --accept-dns=false \
      --ssh
    ${pkgs.coreutils}/bin/rm -f "$auth_key"
  '';
in
{
  # Keep daemon state in memory. Tailscale SSH also needs a var root for
  # host keys, so place its auxiliary state in /run (tmpfs) as well.
  services.tailscale = {
    enable = true;
    useRoutingFeatures = "client";
    extraDaemonFlags = [
      "--state=mem:"
      "--statedir=/run/tailscale"
    ];
  };

  networking.firewall.allowedUDPPorts = [ config.services.tailscale.port ];

  sops = {
    useSystemdActivation = true;
    age.sshKeyPaths = [ "/run/rescue/ssh_host_ed25519_key" ];
    secrets."ts-auth-key" = {
      sopsFile = secrets + "/hosts/${config.networking.hostName}/secrets.yaml";
      key = "tailscale/auth_key";
      mode = "0400";
      restartUnits = [ ];
    };
  };

  environment.systemPackages = [ rescueTailscaleUp ];

  # Drop the temporary SOPS identity after all secrets have been materialized.
  systemd = {
    services = {
      sops-install-secrets.serviceConfig.ExecStartPost = pkgs.writeShellScript "cleanup-rescue-secrets" ''
        ${pkgs.coreutils}/bin/rm -f /run/rescue/ssh_host_ed25519_key
      '';

      tailscale-autoconnect = lib.mkIf wanMode {
        description = "Join WAN rescue node to Tailscale with ACL-managed SSH";
        after = [
          "network-online.target"
          "tailscaled.service"
          "sops-install-secrets.service"
        ];
        wants = [
          "network-online.target"
          "tailscaled.service"
        ];
        requires = [
          "tailscaled.service"
          "sops-install-secrets.service"
        ];
        unitConfig.StartLimitIntervalSec = "0";
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = "10s";
          ExecStart = "${rescueTailscaleUp}/bin/rescue-tailscale-up";
        };
      };
    };

    paths.tailscale-rescue-auth = lib.mkIf wanMode {
      wantedBy = [ "multi-user.target" ];
      pathConfig = {
        PathExists = authKeyPath;
        Unit = "tailscale-autoconnect.service";
      };
    };
  };
}
