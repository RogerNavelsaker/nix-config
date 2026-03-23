# Home Manager impermanence configuration
# This file sets up the basic home-manager persistence structure
# Individual users should configure their specific persisted files/dirs in their own configs
{
  inputs,
  config,
  ...
}:
{
  imports = [ inputs.impermanence.homeManagerModules.impermanence ];

  # Configure home persistence for the v1 standalone Home Manager module.
  home.persistence."/persist${config.home.homeDirectory}" = {
    # Essential files to persist across reboots
    files = [ ];

    # Essential directories to persist
    directories = [ ];

    # Allow other users to access bindfs-mounted files.
    allowOther = true;
  };
}
