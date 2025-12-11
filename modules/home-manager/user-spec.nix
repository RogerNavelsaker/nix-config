{ lib, ... }:
let
  inherit (lib) types mkOption;
in
{
  options.userSpec = {
    username = mkOption {
      type = types.str;
      description = "The username";
    };

    hostname = mkOption {
      type = types.str;
      description = "The hostname for context";
    };

    stateVersion = mkOption {
      type = types.str;
      default = "25.05";
      description = "Home Manager state version";
    };

    enabledFeatures = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "List of enabled feature names";
    };
  };
}
