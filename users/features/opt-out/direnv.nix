# users/features/opt-out/direnv.nix
#
# Direnv with nix-direnv integration for fast shell switching
#
{ config, ... }:
{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;

    # Configuration for direnv
    config = {
      global = {
        warn_timeout = "30s";
        load_dotenv = false;
        strict_env = true;
      };
      whitelist = {
        # Keep workspace-wide trust: per-repo approval is impractical across 90+ repositories.
        prefix = [
          "${config.home.homeDirectory}/Repositories"
        ];
      };
    };

    # Fish integration is automatic when fish is enabled (read-only in new HM)
  };
}
