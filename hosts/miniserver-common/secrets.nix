{ config, secrets, ... }:
{
  sops.useSystemdActivation = true;
  sops.age.sshKeyPaths = builtins.map (hostKey: hostKey.path) (
    builtins.filter (hostKey: hostKey.type == "ed25519") config.services.openssh.hostKeys
  );

  sops.secrets."ts-auth-key" = {
    sopsFile = secrets + "/hosts/${config.networking.hostName}/secrets.yaml";
    key = "tailscale/auth_key";
    mode = "0400";
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    authKeyFile = config.sops.secrets."ts-auth-key".path;
    extraDaemonFlags = [ "--statedir=/var/lib/tailscale" ];
  };

  systemd.services.tailscaled = {
    after = [ "var-lib-tailscale.mount" ];
    requires = [ "var-lib-tailscale.mount" ];
  };

  systemd.services.tailscaled-autoconnect = {
    after = [ "sops-install-secrets.service" ];
    requires = [ "sops-install-secrets.service" ];
  };
}
