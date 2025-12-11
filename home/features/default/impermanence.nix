# Home Manager impermanence configuration
# This file sets up the basic home-manager persistence structure
# Individual users should configure their specific persisted files/dirs in their own configs
{
  inputs,
  config,
  ...
}:
{
  imports = [ inputs.impermanence.nixosModules.home-manager.impermanence ];

  # Configure home persistence - individual users should extend this with their needs
  home.persistence."/persist/${config.home.homeDirectory}" = {
    # Essential files to persist across reboots
    files = [ ];

    # Essential directories to persist
    directories = [ ];

    # Allow other users to use this persistence (needed for some service integrations)
    allowOther = true;
  };
}
