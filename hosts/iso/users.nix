{
  lib,
  config,
  pkgs,
  ...
}:
let
  user = builtins.head config.hostSpec.users;
in
{
  # Persist user's nix profile across reboots
  environment.persistence."/persist".users.${user} = {
    directories = [ ".nix-profile" ];
  };

  users = {
    # User configuration
    mutableUsers = false;

    # Configure the main users (from mkSystem users parameter)
    # Password is automatically configured from secrets by mkSystem builder
    users.${user} = {
      isNormalUser = true;
      group = "${user}";
      shell = pkgs.fish;
      extraGroups = [ "wheel" ];
    };

    # Create user group
    groups.${user} = { };
  };

  # Auto-login to the first user
  services.getty = {
    autologinUser = lib.mkForce (builtins.head config.hostSpec.users);
    helpLine = lib.mkForce "";
  };
}
