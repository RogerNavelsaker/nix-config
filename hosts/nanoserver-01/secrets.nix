{ config, secrets, ... }:
{
  sops.useSystemdActivation = true;
  # Read the persistent source directly: setupSecretsForUsers runs before impermanence links /etc during installation.
  sops.age.sshKeyPaths = [ "/persist/etc/ssh/ssh_host_ed25519_key" ];

  # The auth key is host-specific and supplied through the encrypted host file.
  sops.secrets."ts-auth-key" = {
    sopsFile = secrets + "/hosts/${config.networking.hostName}/secrets.yaml";
    key = "tailscale/auth_key";
    mode = "0400";
  };

  # Persisted state preserves the Tailnet identity across A/B slot updates.
  services.tailscale = {
    enable = true;
    openFirewall = true;
    authKeyFile = config.sops.secrets."ts-auth-key".path;
    extraUpFlags = [ "--ssh" ];
    extraSetFlags = [ "--ssh" ];
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
