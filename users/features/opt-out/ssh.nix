# users/features/opt-out/ssh.nix
#
# SSH configuration managed by Home Manager
# Keys are stored in nix-secrets, config is declarative
#
{ config, ... }:
{
  programs.ssh = {
    enable = true;

    # Disable default config generation (new in HM 25.05)
    enableDefaultConfig = false;

    # Common options via extraConfig
    extraConfig = ''
      # Allow agent forwarding to be set per-host
      AddKeysToAgent yes

      # Reuse connections
      ControlMaster auto
      ControlPath ~/.ssh/sockets/%r@%h-%p
      ControlPersist 600

      # Security
      HashKnownHosts yes
      VisualHostKey no
    '';

    # Host configurations
    matchBlocks = {
      # GitHub with deploy key for nix-secrets
      "github-nix-secrets" = {
        hostname = "github.com";
        user = "git";
        identityFile = "${config.home.homeDirectory}/.ssh/deploy_key_nix-secrets";
        identitiesOnly = true;
      };

      # Default GitHub
      "github.com" = {
        hostname = "github.com";
        user = "git";
        identityFile = "${config.home.homeDirectory}/.ssh/id_ed25519";
        identitiesOnly = true;
      };

      # Local VMs
      "*.local" = {
        user = "rona";
        # TODO: enable forwarding only for an exact host when onward SSH is needed.
        # forwardAgent = true;
      };

      # Tailscale hosts
      "*.ts.net" = {
        user = "rona";
        # TODO: enable forwarding only for an exact host when onward SSH is needed.
        # forwardAgent = true;
      };

      # All hosts - common settings
      "*" = {
        extraOptions = {
          StreamLocalBindUnlink = "yes";
        };
      };
    };
  };

  # Ensure socket directory exists
  home.file.".ssh/sockets/.gitkeep".text = "";
}
